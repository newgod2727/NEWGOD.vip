import tkinter as tk
from tkinter import messagebox
import pyautogui
import threading
import time
import keyboard
import ctypes
import sys
import winsound

NOADMIN_LINE = "NO-ADMIN BUILD - no UAC prompt. Cannot click apps run as admin."

# --- 2. GHOST MODE (Click Through Windows) ---
GWL_EXSTYLE = -20
WS_EX_LAYERED = 0x80000
WS_EX_TRANSPARENT = 0x20

def set_click_through(hwnd, make_transparent):
    try:
        style = ctypes.windll.user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
        if make_transparent:
            ctypes.windll.user32.SetWindowLongW(hwnd, GWL_EXSTYLE, style | WS_EX_LAYERED | WS_EX_TRANSPARENT)
        else:
            ctypes.windll.user32.SetWindowLongW(hwnd, GWL_EXSTYLE, style & ~WS_EX_TRANSPARENT)
    except Exception as e:
        pass

# --- 3. APP VARIABLES ---
pyautogui.FAILSAFE = True
targets = []
running = False

# --- 4. TARGET CLASS (The Circles) ---
class DraggableTarget(tk.Toplevel):
    def __init__(self, master, number):
        super().__init__(master)
        self.number = number
        self.delay = 1.0        # Default delay 1 second
        self.click_type = "single" 
        
        self.overrideredirect(True)
        self.attributes('-topmost', True)
        self.attributes('-transparentcolor', 'white')
        self.config(bg="white")
        
        # Start position
        self.geometry(f"60x60+100+100")

        self.canvas = tk.Canvas(self, width=60, height=60, bg="white", highlightthickness=0)
        self.canvas.pack()
        
        self.circle = self.canvas.create_oval(2, 2, 58, 58, fill="red", outline="black", width=2)
        self.label_num = self.canvas.create_text(30, 20, text=f"{number}", fill="white", font=("Arial", 14, "bold"))
        self.label_info = self.canvas.create_text(30, 40, text=f"{self.delay}s", fill="white", font=("Arial", 9))
        
        # Mouse Events
        self.canvas.bind("<Button-1>", self.start_drag)
        self.canvas.bind("<B1-Motion>", self.do_drag)
        self.canvas.bind("<Button-3>", self.open_settings) # Right Click
        
        self.offset_x = 0
        self.offset_y = 0

    def start_drag(self, event):
        self.offset_x = event.x
        self.offset_y = event.y

    def do_drag(self, event):
        x = self.winfo_x() + event.x - self.offset_x
        y = self.winfo_y() + event.y - self.offset_y
        self.geometry(f"+{x}+{y}")

    def get_center(self):
        return self.winfo_x() + 30, self.winfo_y() + 30

    def update_visuals(self):
        self.canvas.itemconfig(self.label_info, text=f"{self.delay}s")
        if self.click_type == "double":
            self.canvas.itemconfig(self.circle, fill="blue")
        else:
            self.canvas.itemconfig(self.circle, fill="red")

    def open_settings(self, event):
        if running: return # Lock while running
        
        settings = tk.Toplevel(self)
        settings.title("Setup")
        settings.geometry(f"200x180+{self.winfo_x()+70}+{self.winfo_y()}")
        settings.attributes('-topmost', True)

        tk.Label(settings, text=f"Point {self.number}", font=("Arial", 10, "bold")).pack(pady=5)
        
        tk.Label(settings, text="Delay (seconds):").pack()
        e_delay = tk.Entry(settings)
        e_delay.insert(0, str(self.delay))
        e_delay.pack(pady=5)
        
        def toggle():
            if btn_mode.config('text')[-1] == "Single Click":
                btn_mode.config(text="Double Click", bg="#aaaaff")
            else:
                btn_mode.config(text="Single Click", bg="#ffaaaa")

        c_txt = "Double Click" if self.click_type == "double" else "Single Click"
        c_bg = "#aaaaff" if self.click_type == "double" else "#ffaaaa"
        btn_mode = tk.Button(settings, text=c_txt, bg=c_bg, command=toggle)
        btn_mode.pack(pady=5)

        def save():
            try:
                self.delay = float(e_delay.get())
                self.click_type = "double" if "Double" in btn_mode.config('text')[-1] else "single"
                self.update_visuals()
                settings.destroy()
            except:
                messagebox.showerror("Error", "Invalid Number")
                
        tk.Button(settings, text="Save", bg="green", fg="white", command=save).pack(fill='x', padx=10, pady=10)

    def set_ghost(self, ghost):
        hwnd = ctypes.windll.user32.GetParent(self.winfo_id())
        set_click_through(hwnd, ghost)
        if ghost:
            self.attributes('-alpha', 0.4) # Transparent
        else:
            self.attributes('-alpha', 1.0) # Solid

# --- 5. LOGIC & INSTANT STOP ---
def spawn_target():
    t = DraggableTarget(root, len(targets) + 1)
    targets.append(t)

def clear_targets():
    for t in targets: t.destroy()
    targets.clear()

def check_start_key():
    if not running: start_clicking()

# THE MAGIC FUNCTION: Waits without freezing
def instant_wait(seconds):
    end_time = time.time() + seconds
    while time.time() < end_time:
        if keyboard.is_pressed('alt'):
            return False # ALT PRESSED! ABORT!
        time.sleep(0.01) # Sleep 10ms only
    return True

def start_clicking():
    global running
    if running or not targets: return
    
    running = True
    winsound.Beep(400, 100) # LOW BEEP (Start)
    status_label.config(text="RUNNING... (Press ALT to Stop)", fg="green")
    
    # Hide targets from mouse clicks
    for t in targets: t.set_ghost(True)
    
    threading.Thread(target=click_loop).start()

def click_loop():
    global running
    
    while running:
        for t in targets:
            if not running: break
            
            # 1. Stop Check Immediately
            if keyboard.is_pressed('alt'):
                stop_clicking_safe()
                return

            # 2. Get Coords
            x, y = t.get_center()

            # 3. Prevent Stuck Keys (Anti-ShiftLock)
            keyboard.press_and_release('ctrl') 
            
            # 4. Click
            if t.click_type == 'double':
                pyautogui.doubleClick(x, y)
            else:
                pyautogui.click(x, y)
            
            # 5. Smart Wait (This checks for ALT constantly)
            if not instant_wait(t.delay):
                stop_clicking_safe()
                return

    stop_clicking_safe()

def stop_clicking_safe():
    root.after(0, stop_clicking)

def stop_clicking():
    global running
    if not running: return
    running = False
    
    winsound.Beep(800, 100) # HIGH BEEP (Stop)
    status_label.config(text="STOPPED", fg="red")
    
    # Bring targets back
    for t in targets: t.set_ghost(False)

# --- 6. GUI SETUP ---
root = tk.Tk()
root.title("Instant Auto Clicker [NO ADMIN]")
root.geometry("250x300")
root.attributes('-topmost', True) 

tk.Label(root, text="Instant Auto Clicker", font=("Arial", 14, "bold")).pack(pady=10)
tk.Label(root, text=NOADMIN_LINE, fg="#b06000", font=("Arial", 7),
         wraplength=230, justify="center").pack()

btn_spawn = tk.Button(root, text="+ Spawn Point", bg="blue", fg="white", command=spawn_target)
btn_spawn.pack(pady=5, fill='x', padx=20)
btn_clear = tk.Button(root, text="Clear", command=clear_targets)
btn_clear.pack(pady=2)

tk.Label(root, text="-----------------").pack(pady=5)
status_label = tk.Label(root, text="Ready (Press 's' to Start)", fg="blue")
status_label.pack()
tk.Label(root, text="STOP KEY: ALT", font=("Arial", 12, "bold"), fg="red").pack(pady=10)

# KEYBOARD HOOKS
try:
    keyboard.add_hotkey('s', lambda: root.after(0, check_start_key))
except Exception as exc:
    status_label.config(
        text="'s' hotkey off (%s)" % type(exc).__name__, fg="red")
# Note: ALT is checked manually in the loop for maximum speed

root.mainloop()