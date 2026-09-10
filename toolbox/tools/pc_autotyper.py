import tkinter as tk
from tkinter import ttk
import pyautogui
import threading
import time

class AdvancedAutoTyper:
    def __init__(self, root):
        self.root = root
        self.root.title("Phase Auto Typer")
        self.root.geometry("400x550")
        self.root.resizable(False, False)
        self.root.attributes("-topmost", True)  # Keep window on top

        self.is_running = False
        self.total_cycles = 0

        # --- UI SETUP ---
        tk.Label(root, text="Step-by-Step Typer", font=("Arial", 16, "bold"), fg="#333").pack(pady=10)

        # 1. Content
        frame_text = tk.LabelFrame(root, text="1. Content to Type", font=("Arial", 10, "bold"))
        frame_text.pack(padx=10, pady=5, fill="x")
        
        self.text_entry = tk.Text(frame_text, height=3, font=("Arial", 10))
        self.text_entry.pack(padx=5, pady=5, fill="x")
        self.text_entry.insert("1.0", "Hello World")

        # 2. Timing Settings
        frame_settings = tk.LabelFrame(root, text="2. Timing Configuration", font=("Arial", 10, "bold"))
        frame_settings.pack(padx=10, pady=5, fill="x")

        # Delay after typing text
        tk.Label(frame_settings, text="Wait AFTER typing words (sec):").grid(row=0, column=0, sticky="w", padx=5, pady=5)
        self.wait_time_var = tk.Entry(frame_settings, width=8)
        self.wait_time_var.insert(0, "20")
        self.wait_time_var.grid(row=0, column=1, padx=5)

        # How long to spam Enter
        tk.Label(frame_settings, text="Duration to spam ENTER (sec):").grid(row=1, column=0, sticky="w", padx=5, pady=5)
        self.enter_duration_var = tk.Entry(frame_settings, width=8)
        self.enter_duration_var.insert(0, "10")
        self.enter_duration_var.grid(row=1, column=1, padx=5)

        # 3. Status
        self.status_main = tk.Label(root, text="Status: Ready", font=("Arial", 14, "bold"), fg="gray")
        self.status_main.pack(pady=15)
        
        self.status_sub = tk.Label(root, text="Waiting to start...", font=("Arial", 10), fg="gray")
        self.status_sub.pack()

        # 4. Buttons
        self.start_btn = tk.Button(root, text="START (5s Delay)", bg="#2ecc71", fg="white", 
                                 font=("Arial", 12, "bold"), height=2, width=35, command=self.start_thread)
        self.start_btn.pack(pady=5, padx=10)

        self.stop_btn = tk.Button(root, text="STOP", bg="#e74c3c", fg="white", 
                                font=("Arial", 12, "bold"), height=1, width=35, command=self.stop_typing)
        self.stop_btn.pack(pady=5, padx=10)

    def start_thread(self):
        if not self.is_running:
            self.is_running = True
            self.start_btn.config(state="disabled", bg="gray")
            self.stop_btn.config(state="normal", bg="#e74c3c")
            threading.Thread(target=self.run_logic, daemon=True).start()

    def stop_typing(self):
        self.is_running = False
        self.status_main.config(text="Status: Stopping...", fg="red")

    def run_logic(self):
        try:
            # Get settings
            content = self.text_entry.get("1.0", "end-1c")
            wait_time = int(self.wait_time_var.get())
            enter_duration = int(self.enter_duration_var.get())

            # 5 Second Countdown
            for i in range(5, 0, -1):
                if not self.is_running: return
                self.status_main.config(text=f"Click Target! {i}s", fg="orange")
                time.sleep(1)

            self.total_cycles = 0

            # --- MAIN LOOP ---
            while self.is_running:
                self.total_cycles += 1
                
                # PHASE 1: Type the Words
                self.status_main.config(text=f"Phase 1: Typing Text", fg="blue")
                self.status_sub.config(text=f"Typing: {content[:15]}...")
                pyautogui.write(content)
                
                # PHASE 2: Wait 20 seconds
                self.status_main.config(text=f"Phase 2: Waiting {wait_time}s", fg="#d35400")
                for i in range(wait_time, 0, -1):
                    if not self.is_running: return
                    self.status_sub.config(text=f"Waiting... {i} seconds remaining")
                    time.sleep(1)

                # PHASE 3: Spam Enter for 10 seconds
                self.status_main.config(text=f"Phase 3: Spamming ENTER", fg="purple")
                end_time = time.time() + enter_duration
                
                while time.time() < end_time:
                    if not self.is_running: return
                    
                    remaining = int(end_time - time.time())
                    self.status_sub.config(text=f"Pressing Enter... {remaining}s left")
                    
                    pyautogui.press('enter')
                    time.sleep(0.5) # Press Enter every 0.5 seconds (adjust if needed)

            self.status_main.config(text="Status: Stopped", fg="gray")

        except Exception as e:
            self.status_main.config(text=f"Error: Check Inputs", fg="red")
            print(e)
        
        self.is_running = False
        self.start_btn.config(state="normal", bg="#2ecc71")

if __name__ == "__main__":
    pyautogui.FAILSAFE = True
    root = tk.Tk()
    app = AdvancedAutoTyper(root)
    root.mainloop()