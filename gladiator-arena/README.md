# 角斗士竞技场 (Gladiator Arena)

这是一个 Roblox 游戏项目，使用 Rojo 作为构建工具。

## 安装 Rojo

由于自动安装脚本可能遇到网络问题，请按照以下步骤手动安装 Rojo：

### 方法 1: 使用 Rust (推荐)

1. 首先安装 Rust：
   - 访问 https://rustup.rs/
   - 下载并运行安装程序
   - 重启命令提示符

2. 安装 Rojo：
   ```bash
   cargo install rojo
   ```

### 方法 2: 手动下载

1. 访问 https://github.com/rojo-rbx/rojo/releases
2. 下载最新版本的 `rojo-windows.zip`
3. 解压到项目目录
4. 将解压后的目录添加到系统 PATH 环境变量

### 方法 3: 使用 Chocolatey

如果您有 Chocolatey 包管理器：
```bash
choco install rojo
```

## 运行项目

安装 Rojo 后，在项目目录中运行：

```bash
rojo serve
```

这将启动 Rojo 服务器，您可以在 Roblox Studio 中连接到此服务器来同步文件。

## 项目结构

- `src/client/` - 客户端脚本
- `src/server/` - 服务器脚本
- `default.project.json` - Rojo 项目配置文件

## 故障排除

如果遇到 "rojo: command not found" 错误：
1. 确保 Rojo 已正确安装
2. 确保 Rojo 在系统 PATH 中
3. 重启命令提示符
4. 尝试使用完整路径运行 rojo.exe
