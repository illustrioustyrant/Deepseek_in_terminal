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

# 对话循环
while true; do
  read -rp "<$USER_NAME>: " USER_MESSAGE

  # 处理退出逻辑（仅在多轮对话模式生效）
  if [[ $MULTI_MODE -eq 1 && "$USER_MESSAGE" == "exit" ]]; then
    break
  fi

  echo;echo;
  
  # 更新消息历史（添加用户消息）
  messages=$(jq -c --arg role "user" --arg content "${USER_MESSAGE}${LANGUAGE}" \
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
# 保存对话历史（修改以下部分）
if [[ $SAVE_HISTORY -eq 1 ]]; then
  HISTORY_FILE="$HOME/Documents/dshistory.md"
  mkdir -p "$(dirname "$HISTORY_FILE")"
  
  # 使用 printf 格式化输出（修复乱码）
  DATE=$(date +"%Y-%m-%d %H:%M:%S")
  MODEL_NAME=$(jq -r '.model' <<< "$CONFIG")
  
  # 生成带格式的标题（Markdown兼容）
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
  } >> "$HISTORY_FILE"  # 直接追加到文件（避免中间变量）
fi