import sys
import ctypes
import tkinter as tk
import threading
import time
from pynput import keyboard

NOADMIN_LINE = "NO-ADMIN BUILD - no UAC prompt. Cannot click apps run as admin."

# --- DIRECTX LEFT CLICKING ---
# 0x0002 = Left Mouse Down
# 0x0004 = Left Mouse Up
def click_directx():
    ctypes.windll.user32.mouse_event(0x0002, 0, 0, 0, 0)
    ctypes.windll.user32.mouse_event(0x0004, 0, 0, 0, 0)

# --- MAIN APP ---
class LeftClickerShiftE:
    def __init__(self, root):
        self.root = root
        self.root.title("Left Autoclicker (Shift+E) [NO ADMIN]")
        self.root.geometry("400x350")
        self.root.resizable(False, False)
        
        # Variables
        self.running = False
        self.click_count = 0
        
        # UI
        tk.Label(root, text=NOADMIN_LINE, fg="#b06000",
                 font=("Segoe UI", 8), height=1).pack()
        
        # --- CHANGED LABEL HERE ---
        self.lbl_info = tk.Label(root, text="Press 'Shift + E' to Toggle", font=("Segoe UI", 14, "bold"))
        self.lbl_info.pack(pady=5)
        
        tk.Label(root, text="(Warning: 'E' is usually Inventory)", fg="gray", font=("Segoe UI", 8)).pack()

        self.btn_status = tk.Button(root, text="PAUSED", bg="#b02424", fg="white",
                                    font=("Segoe UI", 14, "bold"), width=15, height=2,
                                    command=self.toggle_clicking)
        self.btn_status.pack(pady=10)

        # Settings
        frame_controls = tk.Frame(root)
        frame_controls.pack(pady=10)
        
        tk.Label(frame_controls, text="Clicks per second:", font=("Segoe UI", 12)).pack(side=tk.LEFT, padx=5)
        # Default 15 CPS
        self.cps_var = tk.StringVar(value="15") 
        self.entry_cps = tk.Entry(frame_controls, textvariable=self.cps_var, font=("Segoe UI", 12), width=8, justify='center')
        self.entry_cps.pack(side=tk.LEFT, padx=5)

        self.lbl_count = tk.Label(root, text="Clicks: 0", font=("Segoe UI", 11))
        self.lbl_count.pack(pady=10)

        tk.Label(root, text="Mode: Left Click (DirectX)", fg="blue", font=("Segoe UI", 8)).pack(side=tk.BOTTOM, pady=5)

        # Background Threads
        self.thread_click = threading.Thread(target=self.clicking_loop)
        self.thread_click.daemon = True
        self.thread_click.start()

        # --- CHANGED HOTKEY HERE ---
        try:
            self.listener = keyboard.GlobalHotKeys({'<shift>+e': self.toggle_clicking})
            self.listener.start()
        except Exception as exc:
            self.listener = None
            self.lbl_info.config(
                text="Hotkey off (%s) - use the button" % type(exc).__name__,
                fg="red")

    def toggle_clicking(self):
        self.running = not self.running
        if self.running:
            self.btn_status.config(text="RUNNING", bg="#28a745")
            self.click_count = 0
            self.update_count_label()
        else:
            self.btn_status.config(text="PAUSED", bg="#b02424")

    def update_count_label(self):
        self.lbl_count.config(text=f"Clicks: {self.click_count}")

    def clicking_loop(self):
        while True:
            if self.running:
                try:
                    try:
                        cps = float(self.cps_var.get())
                    except:
                        cps = 12.0
                    
                    if cps <= 0: cps = 1
                    
                    delay = 1.0 / cps
                    
                    # CLICK LEFT
                    click_directx()
                    
                    self.click_count += 1
                    
                    if self.click_count % 10 == 0:
                        self.root.after(0, self.update_count_label)
                        
                    time.sleep(delay)
                except:
                    time.sleep(0.1)
            else:
                time.sleep(0.01)

if __name__ == "__main__":
    root = tk.Tk()
    app = LeftClickerShiftE(root)
    root.mainloop()