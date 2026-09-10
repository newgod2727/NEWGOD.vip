import tkinter as tk
from tkinter import ttk
import pyautogui
import pynput
from pynput import mouse
import threading
import time

class UltimateTyper:
    def __init__(self, root):
        self.root = root
        self.root.title("智能模拟打字器 v5.0")
        self.root.geometry("400x480")
        self.root.attributes("-topmost", True)

        self.is_listening = False
        self.is_typing = False

        # --- 界面部分 ---
        tk.Label(root, text="【1. 输入打字内容】", font=("微软雅黑", 10, "bold")).pack(pady=5)
        self.text_area = tk.Text(root, height=5, width=45)
        self.text_area.pack(pady=5)
        self.text_area.insert("1.0", "输入你的内容")

        # 设置区域
        frame = tk.Frame(root)
        frame.pack(pady=10)

        tk.Label(frame, text="打字次数:").grid(row=0, column=0, padx=5)
        self.count_var = tk.Entry(frame, width=10)
        self.count_var.insert(0, "1")
        self.count_var.grid(row=0, column=1)

        self.loop_var = tk.BooleanVar(value=False)
        tk.Checkbutton(frame, text="无限循环", variable=self.loop_var).grid(row=0, column=2, padx=10)

        # 延迟设置 - 解决“打开设置”的关键
        tk.Label(root, text="右键点击后的等待时间 (秒):", font=("微软雅黑", 9, "italic")).pack()
        self.wait_time = tk.DoubleVar(value=0.5)
        tk.Scale(root, from_=0.1, to=2.0, resolution=0.1, orient=tk.HORIZONTAL, variable=self.wait_time, length=200).pack()
        tk.Label(root, text="(如果还是打开了设置，请调高这个数值)", font=("微软雅黑", 8), fg="red").pack()

        self.status = tk.Label(root, text="状态: 停止", fg="gray", font=("微软雅黑", 12, "bold"))
        self.status.pack(pady=15)

        self.btn = tk.Button(root, text="开启右键触发 (START)", bg="#2ecc71", fg="white", 
                            font=("微软雅黑", 12, "bold"), width=25, height=2, command=self.toggle)
        self.btn.pack(pady=5)

    def run_typing(self):
        content = self.text_area.get("1.0", "end-1c")
        
        # 步骤 1: 强制关闭右键菜单
        pyautogui.press('esc')
        time.sleep(0.1)
        pyautogui.press('esc') 
        
        # 步骤 2: 等待菜单完全消失 (用户设置的时间)
        time.sleep(self.wait_time.get())

        try:
            if self.loop_var.get():
                while self.is_typing:
                    pyautogui.write(content)
                    pyautogui.press('enter')
                    time.sleep(0.1)
            else:
                num = int(self.count_var.get())
                for _ in range(num):
                    if not self.is_typing: break
                    pyautogui.write(content)
                    pyautogui.press('enter')
                    time.sleep(0.1)
        except Exception as e:
            print(f"Error: {e}")

        self.is_typing = False
        self.status.config(text="状态: 运行结束/等待右键", fg="#27ae60")

    def on_click(self, x, y, button, pressed):
        if button == mouse.Button.right and not pressed and self.is_listening:
            if not self.is_typing:
                self.is_typing = True
                self.status.config(text="状态: 正在打字...", fg="#e74c3c")
                threading.Thread(target=self.run_typing, daemon=True).start()

    def toggle(self):
        if not self.is_listening:
            self.is_listening = True
            self.btn.config(text="停止 (STOP)", bg="#e74c3c")
            self.status.config(text="状态: 监听右键中...", fg="#27ae60")
            self.listener = mouse.Listener(on_click=self.on_click)
            self.listener.start()
        else:
            self.is_listening = False
            self.is_typing = False
            if hasattr(self, 'listener'): self.listener.stop()
            self.btn.config(text="开启右键触发 (START)", bg="#2ecc71")
            self.status.config(text="状态: 停止", fg="gray")

if __name__ == "__main__":
    # 紧急避险：鼠标甩到屏幕左上角可强制退出
    pyautogui.FAILSAFE = True
    root = tk.Tk()
    app = UltimateTyper(root)
    root.mainloop()