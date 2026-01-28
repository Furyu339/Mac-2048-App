#!/usr/bin/env python3
import subprocess
import threading
import time
import tkinter as tk
from tkinter import ttk

OUTPUT = "/tmp/gpu_power.txt"

class App:
    def __init__(self, root):
        self.root = root
        self.root.title("GPU 采样助手")
        self.running = False
        self.thread = None

        frm = ttk.Frame(root, padding=12)
        frm.pack(fill=tk.BOTH, expand=True)

        ttk.Label(frm, text="输入 sudo 密码（只用于本机授权）").pack(anchor="w")
        self.pw = tk.StringVar()
        self.entry = ttk.Entry(frm, textvariable=self.pw, show="*")
        self.entry.pack(fill=tk.X, pady=6)
        self.entry.focus()

        self.status = tk.StringVar(value="未开始")
        ttk.Label(frm, textvariable=self.status).pack(anchor="w", pady=(6, 0))

        btns = ttk.Frame(frm)
        btns.pack(fill=tk.X, pady=8)
        self.start_btn = ttk.Button(btns, text="开始采样", command=self.start)
        self.start_btn.pack(side=tk.LEFT)
        self.stop_btn = ttk.Button(btns, text="停止", command=self.stop, state=tk.DISABLED)
        self.stop_btn.pack(side=tk.LEFT, padx=8)

        ttk.Label(frm, text=f"输出文件：{OUTPUT}").pack(anchor="w", pady=(4, 0))

    def start(self):
        if self.running:
            return
        password = self.pw.get()
        if not password:
            self.status.set("请输入密码")
            return
        # sudo 验证
        try:
            p = subprocess.run(
                ["sudo", "-S", "-v"],
                input=(password + "\n").encode(),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
        except Exception:
            self.status.set("密码错误或无权限")
            return

        self.running = True
        self.start_btn.config(state=tk.DISABLED)
        self.stop_btn.config(state=tk.NORMAL)
        self.status.set("采样中…")

        def loop():
            while self.running:
                try:
                    # 使用 -n 避免再次输入密码
                    subprocess.run(
                        ["sudo", "-n", "powermetrics", "--samplers", "gpu_power", "-n", "1"],
                        stdout=open(OUTPUT, "w"),
                        stderr=subprocess.DEVNULL,
                        check=False,
                    )
                except Exception:
                    pass
                time.sleep(2)

        self.thread = threading.Thread(target=loop, daemon=True)
        self.thread.start()

    def stop(self):
        self.running = False
        self.start_btn.config(state=tk.NORMAL)
        self.stop_btn.config(state=tk.DISABLED)
        self.status.set("已停止")

if __name__ == "__main__":
    root = tk.Tk()
    App(root)
    root.mainloop()
