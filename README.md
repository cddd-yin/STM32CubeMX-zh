# STM32CubeMX 汉化

STM32CubeMX（实测 6.x，`C:\stm32mx软件`）界面汉化方案——**运行时翻译（Java Agent）**，不改任何程序文件、不碰 exe、不反编译、不影响功能，装好即用、一键还原。

## 一句话结论

STM32CubeMX 是 **Swing/AWT** 应用，界面文字**硬编码在 class 里**（没有 `.properties` 语言包机制），主程序还打包在 227 MB 的 exe 内且尾部加密——**改 jar / 改 exe 都不现实**。
因此本项目采用 **Java Agent**：在启动参数里挂一个 9 KB 的 agent，运行时周期性遍历 Swing 组件树，**只把「显示出来的文字」替换成中文**。逻辑、数据、生成代码一概不碰。

| 要求 | 实现 |
|---|---|
| 汉化专业 | 词典驱动（`词库\zh.tsv`），术语统一；带 HTML 文案分段翻译 |
| 补丁别太复杂 | 一个 agent jar + 一个词库 + 启动参数一行；**不动任何程序文件** |
| 桌面快捷方式即可中文 | 参数写进 `STM32CubeMX.l4j.ini`，桌面图标/开始菜单/exe 直接启动即中文 |
| 不影响实际运行 | 只改显示文字（标题/菜单/按钮/标签/提示/表头/选项卡），**不触碰逻辑与数据**；agent 全程异常吞掉，绝不干扰主程序 |
| 汉化流程简单 | 改 `词库\zh.tsv` → 重启即生效；未翻译文字可由「收集模式」自动导出 |

## 原理（30 秒版）

```
STM32CubeMX.exe（壳）
  └─ jre\bin\javaw.exe <l4j.ini 里的参数> -classpath "STM32CubeMX.exe;anything" com.st.microxplorer.maingui.STM32CubeMX
                                     ↑
                        加一行 -javaagent:...\stm32cubemx-zh-agent.jar
```

agent 加载后，每 400 ms 在 Swing 事件线程上走一遍所有窗口：
窗口标题、`JMenu`/`JMenuItem`、`AbstractButton`、`JLabel`、`JTabbedPane` 页签、
`JTable` 表头、`TitledBorder` 标题、各类 tooltip —— 命中词典就替换，未命中原样保留。
**只调用 `setText/setTitle` 这类显示接口**，因此不可能影响业务逻辑。

## 目录结构

```
STM32CubeMX汉化/
├─ README.md
├─ .gitignore
├─ 源码/Stm32CubeMxZhAgent.java     agent 源码（单文件，无第三方依赖）
├─ 词库/
│  ├─ zh.tsv                        汉化词库（en<TAB>zh，* 开头为标题短语），可增补
│  └─ 候选词条.tsv                   从插件 jar 抽取的候选文案（按出现次数排序）
├─ 工具/
│  ├─ 构建.ps1                      用 CubeMX 自带 JDK 编译打包 agent -> 成品
│  ├─ 安装汉化.cmd / .ps1            安装（备份 ini + 释放 agent + 写启动参数）
│  ├─ 还原英文.cmd / .ps1            一键还原
│  ├─ 收集未翻译.cmd                 收集模式安装：把未翻译的界面文字记入发现文件
│  └─ 导出候选词条.ps1               从插件 jar 抽取候选文案
├─ 成品/stm32cubemx-zh-agent.jar    agent 成品（构建产物）
└─ docs/原理与验证.md               技术细节与实测记录
```

## 用法

### 安装（桌面快捷方式直接变中文）

双击 `工具\安装汉化.cmd`。脚本会：
1. 检查 CubeMX 是否在运行；
2. 备份启动配置为 `STM32CubeMX.l4j.ini.zhbak`；
3. 把 agent 与词库释放到 `C:\ProgramData\stm32zh\`（纯 ASCII 路径，避免中文路径问题）；
4. 在 `STM32CubeMX.l4j.ini` 末尾追加一行 `-javaagent:...`。

之后**直接双击桌面 `STM32CubeMX` 图标即为中文**，无需其它操作。

### 还原

双击 `工具\还原英文.cmd`：从 `.zhbak` 恢复启动配置，并删除 `C:\ProgramData\stm32zh\`。

### 维护词库（汉化流程）

1. （可选）双击 `工具\收集未翻译.cmd`，正常使用 CubeMX 逛一圈，未翻译文字会自动记入
   `C:\ProgramData\stm32zh\发现-未翻译.tsv`；
2. 把这些文字翻译后追加进 `词库\zh.tsv`（`英文<TAB>中文`）；
3. 重新运行 `工具\安装汉化.cmd`（不含收集模式）；
4. 重启 CubeMX 即生效。

### 重新构建 agent

```
powershell -ExecutionPolicy Bypass -File 工具\构建.ps1
```

用 CubeMX 自带 JDK（`jre\bin\javac`）编译，输出到 `成品\`。源码改动后需要重新构建并重装。

## 覆盖范围与已知限制

- **覆盖**：窗口标题、菜单栏与全部菜单项、按钮/复选框/单选框、标签、选项卡、表格表头、
  各类提示（tooltip）、分组边框标题；含 `<html>` 富文本标签的分段翻译。
- **不覆盖**（有意为之）：
  - 引脚图/时钟树等**自绘画布**上的文字（`Graphics.drawString`）——里面绝大多数是
    器件型号、引脚名、外设名等**技术名词，本就应保留英文**；
  - 下拉框/列表/表格**单元格里的数据**（如芯片型号、封装）——不翻译，避免影响数据与逻辑；
  - 用户输入框内容。
- **词库覆盖率决定汉化完整度**：v1 词库覆盖主页与常用界面（约 330 条），
  更深层对话框可用「收集模式」逐步补齐；未收录的条目**原样显示英文**，不会出现空白或乱码。

## 实测

2026-10-08 于本机实测（STM32CubeMX 6.x + 自带 Temurin JDK 21.0.3）：

- 桌面快捷方式启动 → 标题 `STM32CubeMX 未命名`、菜单栏 `文件/窗口/帮助`、
  主页 `现有工程 / 打开现有工程 / 新建工程 / 我要： / 从 MCU 开始创建工程 / 进入 MCU 选型 …` 全中文；
- `工具\还原英文.cmd` 可完全恢复原始启动配置；
- 详见 `docs\原理与验证.md`。
