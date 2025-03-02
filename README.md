# Deepseek_in_terminal

![CLI Tool](https://img.shields.io/badge/CLI-Tool-brightgreen) 
![License](https://img.shields.io/badge/License-MIT-blue)

## 项目简介
一个基于macOS终端的DeepSeek命令行工具，灵感来源于NJUJYY项目。通过简单的命令交互，直接调用DeepSeek API实现智能对话和推理功能，支持流式响应和多轮对话。

## 功能特性
- 🚀 支持`deepseek-chat`和`deepseek-reasoner`双模型
- 🌡️ 可调节`temperature`参数控制输出随机性
- 🇨🇳 默认中文输出，支持`-e`参数切换至提问语言
- 💬 支持单次对话（`ads`）和持续多轮对话（`adsm`）

## 安装指南

### 依赖安装
1. 安装JSON解析工具`jq`：
   ```bash
   brew install jq
   ```

### 脚本配置
1. 下载项目文件：
   ```bash
   git clone https://github.com/yourusername/Deepseek_in_terminal.git
   cd Deepseek_in_terminal
   ```

2. **替换API密钥**（重要！）：
   用文本编辑器打开`ads.sh`和`adsm.sh`，找到以下行：
   ```bash
   API_KEY="<you_deepseek_API>"  # 替换为你的API Key
   ```
   替换<you_deepseek_API>为[您的DeepSeek API Key](https://platform.deepseek.com/api-keys)

3. 赋予执行权限：
   ```bash
   chmod +x ads.sh adsm.sh
   ```

4. 安装到系统路径：
   ```bash
   sudo mv ads.sh /usr/local/bin/ads
   sudo mv adsm.sh /usr/local/bin/adsm
   ```

## 使用说明

### 单次对话模式
```bash
ads [参数] [temperature值]
```
示例：
```bash
ads -r1 0.8   # 使用reasoner模型，temperature=0.8
ads -e        # 输出英文回复
```

### 多轮对话模式
```bash
adsm [参数] [temperature值]
```
示例：
```bash
adsm -v3      # 进入chat模型的持续对话
输入"exit"退出对话
```

### 参数说明
| 参数 | 功能                          |
|------|-----------------------------|
| -v3  | 使用chat模型（默认）           |
| -r1  | 使用reasoner模型              |
| -e   | 输出英文（默认中文）           |
| 数值 | 设置temperature（范围0.0-2.0）|



## 版本信息
当前版本：**V1.0发行版**  
更新日期：2025-03-03

## 相关链接
- [DeepSeek官方API文档](https://api-docs.deepseek.com/)
- [jq工具官方文档](https://stedolan.github.io/jq/)

## 许可证
本项目采用 **[MIT License](LICENSE)** 开源协议
```

> 提示：实际使用时请确保：
> 1. 已申请有效的DeepSeek API密钥
> 2. macOS系统版本>=10.15
> 3. 已正确安装Homebrew包管理器
> 4. 移动文件到系统路径时需要输入管理员密码