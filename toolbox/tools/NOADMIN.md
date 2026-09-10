## 無管理員版本

學校 desktop 關掉了管理員權限。原本十件工具裡面有七個檔一開機就叫 UAC,
叫不到就整個 `sys.exit()` 死掉,連一個窗都不會出。

每一個這樣的檔現在多一個 `-noadmin.py` 兄弟檔。它們永遠不叫 UAC,
不會自己重開,窗上面自己寫住「我是無管理員版本」同埋失去了什麼。

原本那批檔一個字都沒有動。兩個版本並排放,揀哪個就雙擊哪個。

## 有無管理員版本的七個

| 檔案 | 無管理員版本 | 原本要管理員來做什麼 | 無管理員版本失去什麼 |
|---|---|---|---|
| autoclicker21.py | autoclicker21-noadmin.py | 把 `mouse_event` 的左鍵射入本身以管理員身分跑的視窗 | 打不入以管理員身分跑的視窗;Shift+E 在那種視窗前面也不會響 |
| minecraft_rightclicker.py | minecraft_rightclicker-noadmin.py | 同上,右鍵 | 同上,Shift+R |
| minecraft_mining_holder.py | minecraft_mining_holder-noadmin.py | 同上,按住左鍵 | 同上,Shift+T |
| minecraft_sequence_clicker.py | minecraft_sequence_clicker-noadmin.py | 同上,加 `keybd_event` 的數字鍵 scan code | 同上,Shift+C |
| clcik with chosing.py | clcik with chosing-noadmin.py 同 clcik-with-chosing-noadmin.py | pyautogui 同 keyboard 射入以管理員身分跑的視窗 | 同上;`s` 開始鍵在那種視窗前面不會響 |
| GOLDMACRO_v3.py | GOLDMACRO_v3-noadmin.py | 錄同放的時候要跨過管理員視窗那道界 | 錄不到、放不入以管理員身分跑的視窗 |
| GOLDMACRO_v4.py | GOLDMACRO_v4-noadmin.py | 同上 | 同上 |

兩個 `clcik ... -noadmin.py` 是逐個位元組一樣的兩份,因為網址載不到有空格那個名。

## 那七個失去的其實是同一樣東西

Windows 有一條叫 UIPI 的界:低權限的程式射不入高權限的視窗,
連鍵盤 hook 都收不到那個視窗前面按的鍵。管理員身分就是用來跨過那條界。

所以在學校那部機上面,這個代價通常等於零 —— 那部機根本沒有東西以管理員身分跑,
沒有界要跨。真正會失去東西的情況只有一種:目標本身是用「以系統管理員身分執行」開的。

## 無管理員版本額外做了的一件事

原本那批檔的熱鍵是在 `__init__` 裡面直接開,開不到就整個窗死在畫出來之前,
而且錯誤只會掉進一個沒有人在看的 console。無管理員版本把那一句包起來:
熱鍵開不到就在窗裡面那行字寫「Hotkey off」再叫他撳掣,其餘功能照跑。

## 本身就不需要管理員的四個

| 檔案 | 為什麼不用 |
|---|---|
| pc_autotyper.py | 只有 tkinter 加 pyautogui,零個權限呼叫 |
| typewordinf.py | 只有 tkinter 加 pyautogui 加 pynput,零個權限呼叫 |
| farm_watch.py | 只讀自己那堆檔;讀不到高權限進程的 open_files 時它自己已經識得靜靜跳過 |
| bootstrap.py | 只做檢查,而且它本身就叫人不要把 PyToolbox 放進要管理員的資料夾 |

這四個沒有 `-noadmin.py`,因為它們原本那一份已經是無管理員版本。

## 量到的證據

在一部 Windows 11 desktop 上面,用一個 Safer NORMALUSER token 開的進程
(`IsUserAnAdmin` 回 0,同學校那部機一樣)去跑:

| 跑的檔 | 結果 |
|---|---|
| autoclicker21.py 原本那個 | 1 秒內死,0 個窗 |
| autoclicker21-noadmin.py | 10 秒全部活住,窗標題 `Left Autoclicker (Shift+E) [NO ADMIN]` |
| minecraft_rightclicker-noadmin.py | 10 秒全部活住,窗標題 `Minecraft Right-Clicker (Shift+R) [NO ADMIN]` |
| clcik-with-chosing-noadmin.py | 10 秒全部活住,窗標題 `Instant Auto Clicker [NO ADMIN]` |
| GOLDMACRO_v4-noadmin.py | 10 秒全部活住,窗開得出 |

五次全部 0 個 `consent.exe`,即是一次 UAC 都沒有彈過。
七個無管理員版本裡面 `grep runas` 同 `grep ShellExecuteW` 都是零命中。
