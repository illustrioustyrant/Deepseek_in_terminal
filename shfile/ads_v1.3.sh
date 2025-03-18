#!/bin/bash

API_KEY="<your key>"
USER_NAME=$(whoami)
LANGUAGE="(answer in Chinese)"

# 读取配置文件
CONFIG_FILE="$HOME/.dsconfig"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "错误：配置文件 $CONFIG_FILE 不存在" >&2
  exit 1
fi

CONFIG=$(cat "$CONFIG_FILE")
messages=$(jq -c '.messages' <<< "$CONFIG")

# 初始化参数变量
MULTI_MODE=0
SAVE_HISTORY=0

# 参数解析
while [[ $# -gt 0 ]]; do
  case $1 in
    -e)
      LANGUAGE=""
      shift
      ;;
    -m)
      MULTI_MODE=1
      shift
      ;;
    -h)
      SAVE_HISTORY=1
      shift
      ;;
    -a)
      echo "用法: $0 [选项]"
      echo "选项:"
      echo "  -a         显示此帮助信息"
      echo "  -e         禁用中文回答（不添加 '(answer in Chinese)'）"
      echo "  -m         启用多轮对话模式（输入 'exit' 退出）"
      echo "  -h         保存对话历史到文件 ~/Documents/dshistory.md"
      echo
      echo "其他:"
      echo " @file:../../abc:   可以读取本地文件"
      echo " enter              可以换行"
      echo " ^D                 在新的一行使用ctrlD发送"
      exit 0
      ;;
    -*)
      echo "错误：无效选项 $1" >&2
      exit 1
      ;;
    *)
      echo "错误：未知参数 $1" >&2
      exit 1
      ;;
  esac
done

# 将 (answer in Chinese) 添加到 system 消息的开头
messages=$(jq -c --arg lang "$LANGUAGE" \
  'map(if .role == "system" then .content = $lang + "\n" + .content else . end)' \
  <<< "$messages")

# 对话循环
while true; do
  echo -n "<$USER_NAME>: " >&2
  USER_MESSAGE=""  # 初始化用户输入
  while IFS= read -r -e line; do
    # 如果用户输入为空（直接按回车），则添加一个空行
    if [[ -z "$line" ]]; then
      USER_MESSAGE+=$'\n'
    else
      USER_MESSAGE+="$line"$'\n'
    fi
  done
  # 移除最后一个多余的换行符
  USER_MESSAGE="${USER_MESSAGE%$'\n'}"

  # 处理退出逻辑（保持不变）
  if [[ $MULTI_MODE -eq 1 && "$USER_MESSAGE" == "exit" ]]; then
    break
  fi

  # 其余代码保持不变...

  # ====== 新增@file:...:处理逻辑 ======
  while [[ "$USER_MESSAGE" =~ @file:([^:]+): ]]; do
    # 提取捕获组中的路径
    file_path="${BASH_REMATCH[1]}"
    # 解析路径（处理波浪号和空格）
    resolved_path=$(eval echo "$file_path")
    if [[ ! -f "$resolved_path" ]]; then
      echo "错误：文件 $resolved_path 不存在" >&2
      exit 1
    fi
    # 读取文件内容（保留换行符）
    file_content=$(<"$resolved_path")
    # 在文件内容前后添加换行符
    file_content=$'\n'$'\n'"${file_content}"$'\n'$'\n'
    # 替换完整模式（包括前后冒号）
    USER_MESSAGE="${USER_MESSAGE/@file:${file_path}:/$file_content}"
  done

  echo;echo;

  # 更新消息历史（添加用户消息）
  messages=$(jq -c --arg role "user" --arg content "${USER_MESSAGE}" \
    '. + [{"role": $role, "content": $content}]' <<< "$messages")

  # 构建请求数据（使用配置文件参数并替换messages）
  DATA=$(jq -c --argjson messages "$messages" '.messages = $messages' <<< "$CONFIG")

  # 处理响应
  MODEL=$(jq -r '.model' <<< "$CONFIG")
  TEMPERATURE=$(jq -r '.temperature' <<< "$CONFIG")
  echo  "<$MODEL,$TEMPERATURE>: "
  temp_file=$(mktemp)

  # 非流式处理
  if [[ $(jq -r '.stream' <<< "$CONFIG") == "false" ]]; then
    RESPONSE=$(curl -s -X POST https://api.deepseek.com/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "$DATA")

    CONTENT=$(jq -r '
      .choices[0].message |
      ((.reasoning_content // "") + (.content // ""))
    ' <<< "$RESPONSE")

    printf "%b" "$CONTENT" | tee "$temp_file"
    echo -e "\n\n"

  else
    # 流式处理逻辑
    BUT=0
    curl -s -X POST https://api.deepseek.com/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "$DATA" | while IFS= read -r line; do
      if [[ "$line" == data:* ]]; then
        [[ "$line" == *"[DONE]"* ]] && { echo -e "\n\n"; break; }

        JSON_DATA=$(sed 's/^data: //; s/\\n/\\\\n/g' <<< "$line")
        CONTENT=$(jq -r '.choices[0].delta | if .content == null then .reasoning_content else .content end' <<< "$JSON_DATA")
        RAW_CONTENT=$(jq -r '.choices[0].delta.content' <<< "$JSON_DATA")

        # 特殊格式处理（仅限reasoner模型）
        if [[ "$MODEL" == "deepseek-reasoner" ]]; then
          if (( BUT == 0 )) && [[ "$RAW_CONTENT" != "null" ]]; then
            BUT=1
            echo -e "\n\n"
          fi
        fi

        [[ -n "$CONTENT" ]] && printf "%b" "$CONTENT" | tee -a "$temp_file"
      fi
    done
  fi

  # 更新对话历史（添加助手回复）
  assistant_content=$(cat "$temp_file")
  rm "$temp_file"
  messages=$(jq -c --arg role "assistant" --arg content "$assistant_content" \
    '. + [{"role": $role, "content": $content}]' <<< "$messages")

  # 单次对话模式退出
  if [[ $MULTI_MODE -eq 0 ]]; then
    break
  fi
done

# 保存对话历史
if [[ $SAVE_HISTORY -eq 1 ]]; then
  HISTORY_FILE="$HOME/Documents/dshistory.md"
  mkdir -p "$(dirname "$HISTORY_FILE")"

  DATE=$(date +"%Y-%m-%d %H:%M:%S")
  MODEL_NAME=$(jq -r '.model' <<< "$CONFIG")

  {
    printf "\n## 记录时间：%s | 模型名称：%s\n\n" "$DATE" "$MODEL_NAME"

    jq -c '.[]' <<< "$messages" | while IFS= read -r message; do
      ROLE=$(jq -r '.role' <<< "$message")
      CONTENT=$(jq -r '.content' <<< "$message" | sed 's/\\n/\n/g')

      case $ROLE in
        "user")      printf "**%s**: %s\n\n" "$USER_NAME"  "$CONTENT" ;;
        "assistant") printf "**%s**:\n\n %s\n\n" "$MODEL_NAME" "$CONTENT" ;;
        "$ROLE")     printf "**%s**: %s\n\n"   "$ROLE"      "$CONTENT" ;;
      esac
    done
  } >> "$HISTORY_FILE"
fi
