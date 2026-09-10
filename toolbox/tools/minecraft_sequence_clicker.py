import sys
import ctypes
import tkinter as tk
import threading
import time
from pynput import keyboard

# --- ADMIN CHECK & RESTART ---
def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

if not is_admin():
    ctypes.windll.shell32.ShellExecuteW(
        None, "runas", sys.executable, " ".join(sys.argv), None, 1
    )
    sys.exit()

# --- DIRECTX INPUT CODES ---
# Scan codes for number keys (1-9, 0)
SCAN_CODES = {
    '1': 0x02, '2': 0x03, '3': 0x04, '4': 0x05, '5': 0x06,
    '6': 0x07, '7': 0x08, '8': 0x09, '9': 0x0A, '0': 0x0B
}

def click_right_directx():
    # 0x0008 = Right Down, 0x0010 = Right Up
    ctypes.windll.user32.mouse_event(0x0008, 0, 0, 0, 0)
    ctypes.windll.user32.mouse_event(0x0010, 0, 0, 0, 0)

def press_key_directx(key_char):
    if key_char in SCAN_CODES:
        hex_code = SCAN_CODES[key_char]
        # 0x0008 in keybd_event is actually Scancode flag if using extended
        # Standard keybd_event: (bVk, bScan, dwFlags, dwExtraInfo)
        # Use simple mapVirtualKey logic or direct scan code injection
        
        # Press Down
        ctypes.windll.user32.keybd_event(0, hex_code, 0x0008, 0)
        # Release Up (0x0008 | 0x0002)
        ctypes.windll.user32.keybd_event(0, hex_code, 0x0008 | 0x0002, 0)

# --- MAIN APP ---
class SequenceRightClicker:
    def __init__(self, root):
        self.root = root
        self.root.title("MC Sequence Clicker (Shift+C)")
        self.root.geometry("600x450")
        self.root.resizable(False, False)
        
        # Variables
        self.running = False
        self.click_count = 0
        self.sequence_slots = [""] * 10  # Stores the 10 "Will Do" slots
        
        # --- UI SETUP ---
        
        # Header
        tk.Label(root, text="Right Click + Sequence", font=("Segoe UI", 16, "bold")).pack(pady=5)
        self.lbl_info = tk.Label(root, text="Press 'Shift + C' to Toggle", font=("Segoe UI", 12))
        self.lbl_info.pack()
        
        self.btn_status = tk.Button(root, text="PAUSED", bg="#b02424", fg="white",
                                    font=("Segoe UI", 14, "bold"), width=20, height=2,
                                    command=self.toggle_clicking)
        self.btn_status.pack(pady=10)

        # --- LINE 1: WILL DO (Active Sequence) ---
        tk.Label(root, text="Line 1: Will Do (Sequence Order)", font=("Segoe UI", 10, "bold"), fg="green").pack(pady=(10, 0))
        
        frame_active = tk.Frame(root, bg="#dddddd", pady=10)
        frame_active.pack(fill="x", padx=10)
        
        self.active_btns = []
        for i in range(10):
            # Create 10 slots
            btn = tk.Button(frame_active, text="", width=4, height=2, font=("Segoe UI", 10, "bold"),
                            bg="white", command=lambda idx=i: self.remove_from_sequence(idx))
            btn.pack(side=tk.LEFT, padx=5, expand=True)
            self.active_btns.append(btn)

        # --- LINE 2: WON'T DO (Pool) ---
        tk.Label(root, text="Line 2: Won't Do (Available Keys)", font=("Segoe UI", 10, "bold"), fg="red").pack(pady=(20, 0))
        
        frame_pool = tk.Frame(root, pady=5)
        frame_pool.pack(fill="x", padx=10)
        
        self.pool_btns = {}
        keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']
        for k in keys:
            btn = tk.Button(frame_pool, text=k, width=4, height=2, font=("Segoe UI", 10),
                            command=lambda key=k: self.add_to_sequence(key))
            btn.pack(side=tk.LEFT, padx=5, expand=True)
            self.pool_btns[k] = btn

        # --- SETTINGS ---
        frame_controls = tk.Frame(root)
        frame_controls.pack(pady=20)
        
        tk.Label(frame_controls, text="Right Click CPS:", font=("Segoe UI", 11)).pack(side=tk.LEFT, padx=5)
        self.cps_var = tk.StringVar(value="12") 
        self.entry_cps = tk.Entry(frame_controls, textvariable=self.cps_var, font=("Segoe UI", 11), width=5, justify='center')
        self.entry_cps.pack(side=tk.LEFT, padx=5)
        
        tk.Label(frame_controls, text="(Sequence delay is fixed at 0.1s)", fg="gray").pack(side=tk.LEFT, padx=10)

        # --- THREADS ---
        # 1. Thread for Right Clicking (High Speed)
        self.thread_click = threading.Thread(target=self.right_click_loop)
        self.thread_click.daemon = True
        self.thread_click.start()
        
        # 2. Thread for Sequence Keys (Slower, 0.1s delay)
        self.thread_seq = threading.Thread(target=self.sequence_loop)
        self.thread_seq.daemon = True
        self.thread_seq.start()

        # Hotkey Listener
        self.listener = keyboard.GlobalHotKeys({'<shift>+c': self.toggle_clicking})
        self.listener.start()

    # --- UI LOGIC ---
    def add_to_sequence(self, key):
        # Find first empty slot in active_btns
        for i in range(10):
            if self.sequence_slots[i] == "":
                self.sequence_slots[i] = key
                self.active_btns[i].config(text=key, bg="#c3e6cb") # Light green
                self.pool_btns[key].config(state=tk.DISABLED, bg="#f0f0f0") # Disable in pool
                return

    def remove_from_sequence(self, idx):
        key = self.sequence_slots[idx]
        if key != "":
            # Clear the slot
            self.sequence_slots[idx] = ""
            self.active_btns[idx].config(text="", bg="white")
            
            # Re-enable in pool
            if key in self.pool_btns:
                self.pool_btns[key].config(state=tk.NORMAL, bg="SystemButtonFace")
            
            # Optional: Shift remaining items to left? 
            # User said "can leave some blank", so we won't auto-shift. We keep the gap.

    def toggle_clicking(self):
        self.running = not self.running
        if self.running:
            self.btn_status.config(text="RUNNING", bg="#28a745")
        else:
            self.btn_status.config(text="PAUSED", bg="#b02424")

    # --- LOOPS ---
    def right_click_loop(self):
        """ Handles the mouse clicking at defined CPS """
        while True:
            if self.running:
                try:
                    try:
                        cps = float(self.cps_var.get())
                    except:
                        cps = 12.0
                    if cps <= 0: cps = 1
                    delay = 1.0 / cps
                    
                    click_right_directx()
                    time.sleep(delay)
                except:
                    time.sleep(0.1)
            else:
                time.sleep(0.01)

    def sequence_loop(self):
        """ Handles the number keys with 0.1s delay """
        while True:
            if self.running:
                # Iterate through the 10 slots
                items_pressed = False
                for key in self.sequence_slots:
                    if not self.running: break # Stop immediately if paused
                    
                    if key != "":
                        # Constraint: "it will have 0.1sec daley , that press 2, 1, 5"
                        press_key_directx(key)
                        items_pressed = True
                        time.sleep(0.1) 
                
                # If no items are in the sequence, just sleep a bit to save CPU
                if not items_pressed:
                    time.sleep(0.1)
            else:
                time.sleep(0.01)

if __name__ == "__main__":
    root = tk.Tk()
    app = SequenceRightClicker(root)
    root.mainloop()