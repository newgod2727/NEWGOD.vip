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

# --- DIRECTX MOUSE EVENTS ---
# 0x0002 = Left Mouse Down
# 0x0004 = Left Mouse Up
def hold_left_down():
    ctypes.windll.user32.mouse_event(0x0002, 0, 0, 0, 0)

def release_left_up():
    ctypes.windll.user32.mouse_event(0x0004, 0, 0, 0, 0)

# --- MAIN APP ---
class MiningHolder:
    def __init__(self, root):
        self.root = root
        self.root.title("Minecraft AFK Miner (Shift+T)")
        self.root.geometry("400x250")
        self.root.resizable(False, False)
        
        # Variables
        self.running = False
        
        # UI Setup
        tk.Label(root, text="", height=1).pack()
        
        self.lbl_info = tk.Label(root, text="Press 'Shift + T' to Toggle", font=("Segoe UI", 14, "bold"))
        self.lbl_info.pack(pady=5)
        
        tk.Label(root, text="(Holds Left Click continuously)", fg="gray", font=("Segoe UI", 10)).pack()

        self.btn_status = tk.Button(root, text="PAUSED", bg="#b02424", fg="white",
                                    font=("Segoe UI", 16, "bold"), width=15, height=2,
                                    command=self.toggle_mining)
        self.btn_status.pack(pady=20)

        tk.Label(root, text="Status: Waiting...", fg="black", font=("Segoe UI", 10)).pack(side=tk.BOTTOM, pady=10)

        # Background Thread
        self.thread_mine = threading.Thread(target=self.mining_loop)
        self.thread_mine.daemon = True
        self.thread_mine.start()

        # Hotkey Listener
        self.listener = keyboard.GlobalHotKeys({'<shift>+t': self.toggle_mining})
        self.listener.start()

    def toggle_mining(self):
        self.running = not self.running
        if self.running:
            self.btn_status.config(text="MINING...", bg="#28a745") # Green
            self.root.title("MINING ACTIVE - Shift+T to Stop")
        else:
            self.btn_status.config(text="PAUSED", bg="#b02424") # Red
            self.root.title("Minecraft AFK Miner (Shift+T)")
            # Force release immediately when paused
            release_left_up()

    def mining_loop(self):
        while True:
            if self.running:
                # We send the "Down" signal repeatedly.
                # In Minecraft, this ensures that if you lag or the focus slips, 
                # it immediately re-applies the "Hold" status.
                hold_left_down()
                time.sleep(0.05) # Small sleep to prevent freezing CPU
            else:
                # If we are not running, ensure the mouse is UP.
                # We loop this slowly just to be safe.
                release_left_up()
                time.sleep(0.1)

if __name__ == "__main__":
    root = tk.Tk()
    app = MiningHolder(root)
    # Safety: If the window is closed, ensure mouse is released
    def on_closing():
        app.running = False
        release_left_up()
        root.destroy()
        sys.exit()
        
    root.protocol("WM_DELETE_WINDOW", on_closing)
    root.mainloop()