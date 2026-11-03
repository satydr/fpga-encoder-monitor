# 把项目传到 GitHub（照着做，约 10 分钟）

> 本地部分我已经做完了：**仓库已建好、135 个文件已提交、3.7 GB 的 Vivado 垃圾已排除**。
> 你只需要做网页上的 3 件事 + 敲 3 条命令。

---

---

## ⚠️ 先说一件事：你电脑上没装 Git

找不到 Git Bash 是正常的——**你之前用的 git 是 WorkBuddy 自带的便携版**（藏在 `D:\workbuddy\resources\vendor\PortableGit`），它不在开始菜单里，也不在 PowerShell 的命令搜索路径中。

所以别去找 Git Bash 了，**二选一**：

| 路线 | 怎么做 | 适合 |
|---|---|---|
| **① 双击 bat（零安装，推荐现在用）** | 直接双击 `E:\project\上传GitHub.bat`，粘地址、回车、登录，完事 | 只想赶紧传上去 |
| ② 装 Git for Windows（以后都方便） | PowerShell 里跑一行：`winget install --id Git.Git -e`，装完右键菜单就有 "Git Bash Here" | 以后还要维护仓库 |

> 还有个更省事的图形化选择：**GitHub Desktop**（desktop.github.com 下载安装）→ 登录 → Add Existing Repository → 选 `E:\project` → Publish repository → 勾掉 Keep this code private。全程点鼠标，不用令牌。

---

## 第 0 步 · 已经替你做好的（不用管，看一眼就行）

| 项 | 状态 |
|---|---|
| `git init` 建仓库 | ✅ 已做（`E:\project\.git`） |
| `.gitignore` 排除 Vivado 缓存 | ✅ 已写（`.cache/.hw/.sim/.ip_user_files/.runs` 全排除，只留 `.bit` 比特流） |
| `README.md` 首页介绍 | ✅ 已写（作品说明 + 信号链 + 实测指标 + 复现步骤） |
| 首次提交 | ✅ 已提交，135 个文件，**26 MB** |
| 配置作者名 | ⚠️ 暂用占位 `HuYi-51528`，**想改看文末第 5 步** |

---

## 第 1 步 · 在 GitHub 上建一个空仓库（网页）

1. 打开 <https://github.com> → 注册/登录（用你自己的邮箱）。
2. 右上角 **+** → **New repository**。
3. 填：
   - **Repository name**：`fpga-encoder-monitor`（或 `51528-fpga-encoder`）
   - **Description**：`面向运动控制场景的 FPGA 高速编码器信号解析与在线状态预警系统（EGO1 / XC7A35T）`
   - **Public**（公开，**必须选 Public**，否则评委打不开）
   - **不要勾选** Add a README file / .gitignore / license（本地已经有了，勾了会冲突）
4. 点 **Create repository**。
5. 建好后页面上会有一串地址，复制 **HTTPS** 那个，形如：
   `https://github.com/你的用户名/fpga-encoder-monitor.git`

---

## 第 2 步 · 生成"通行令牌"（Token，网页）

GitHub 已经不支持用密码推送了，必须用令牌。**只做一次**：

1. 右上角头像 → **Settings** → 左侧最下面 **Developer settings**
2. **Personal access tokens** → **Fine-grained tokens** → **Generate new token**
3. 填：
   - Token name：`pc-push`
   - Expiration：90 days
   - Repository access：**Only select repositories** → 选刚才那个仓库
   - Permissions → **Contents**：改成 **Read and write**
4. **Generate token** → **立刻复制那一串 `github_pat_...`**（关掉页面就再也看不到了，先粘到记事本里）

---

## 第 3 步 · 推上去（**不用敲命令，双击就行**）

**双击 `E:\project\上传GitHub.bat`**，跟着提示做：

1. 屏幕问你要仓库地址 → 把第 1 步复制的 `https://github.com/...git` **粘贴进去**（bat 里右键就是粘贴），回车；
2. 开始推送，**会弹出登录窗口**：用户名填 GitHub 用户名，**密码栏填令牌 `github_pat_...`**；如果弹的是浏览器，直接登录授权就行；
3. 看到 `Branch 'main' set up to track` 就是成功了，刷新 GitHub 页面能看到 135 个文件。

> 想手动敲也行（PowerShell 里，把三条里的 git 换成完整路径）：
> ```powershell
> $g = 'D:\workbuddy\resources\vendor\PortableGit\mingw64\bin\git.exe'
> & $g -C E:\project remote add origin https://github.com/你的用户名/仓库名.git
> & $g -C E:\project push -u origin main
> ```

---

## 第 4 步 · 把链接交上去

- 仓库地址：`https://github.com/你的用户名/fpga-encoder-monitor`
- 填进报名系统 / 提交材料的"开源链接"一栏；**确认仓库是 Public**（头像页能看到，不是 404）。

---

## 第 5 步 · 可选：把作者名改成本人

在 PowerShell 里跑（因为没装 Git，这里要用完整路径）：

```powershell
$g = 'D:\workbuddy\resources\vendor\PortableGit\mingw64\bin\git.exe'
& $g -C E:\project config user.name  "你的名字"
& $g -C E:\project config user.email "你的GitHub注册邮箱"
& $g -C E:\project commit --amend --reset-author --no-edit
& $g -C E:\project push -f
```

---

## 翻车怎么办

| 症状 | 处理 |
|---|---|
| 双击 bat 后黑窗口一闪就没了 | 打开 PowerShell，粘贴这行运行，窗口会**停住**让你看报错：`cmd /k "E:\project\上传GitHub.bat"`（bat 已改为 CRLF + GBK 编码，本不应再闪退） |
| `fatal: remote origin already exists` | 说明已加过，直接跑第 2、3 条即可 |
| `Failed to connect / 443 timed out` | 国内连 GitHub 常不稳：换个网络（手机热点）、或开代理；实在不行改 **Gitee**：在 gitee.com 建空仓库，命令完全一样，只是网址换成 `https://gitee.com/用户名/仓库名.git`，速度快得多，比赛一般也认可 |
| 弹窗输密码后仍报 `Authentication failed` | 密码栏必须填 **token** 不是账号密码；token 权限要勾 Contents: Read and write |
| `src refspec main does not match any` | 本地没提交成功，先跑 `git log --oneline` 看有没有那条提交 |
| 提示文件太大（>100 MB） | 单文件超 100 MB 会被拒；本项目最大 2.1 MB，不会出现 |

---

## 两个提醒

1. **隐私**：报告和 README 里有组号 51528 和成员姓名学号。公开仓库意味着任何人可搜到——参赛作品一般没问题，但如果你介意，我可以把封面姓名那几处改成"参赛组 51528"。
2. **水文印**：`提交材料/照片/原始_全局照.jpg` 左下角有 vivo 水印、左上角有钥匙串，这张原图也被传上去了。要不要我从仓库里去掉（只留裁好的那几张）？
