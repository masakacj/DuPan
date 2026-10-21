#!/usr/bin/env bash
# Grant the existing mcpdebian SSH key access to 192.168.233.233.
# Execute ON 192.168.233.233: sudo bash grant_mcpdebian_ssh_233.sh [target_username]
set -euo pipefail

SOURCE_IP='192.168.233.137'
TARGET_IP='192.168.233.233'
PUBKEY_TYPE='ssh-ed25519'
PUBKEY_DATA='AAAAC3NzaC1lZDI1NTE5AAAAIF2jjBrjZ55ni+cb3S0s/Qq8UWexV8DNHykr2OnN6jbG'
EXPECTED_HOST_FINGERPRINT='SHA256:/XHkeonv4RVSViGwHgcdiVpNXs8XGEJd1nEzTWTakwA'
KEY_COMMENT='mcpdebian-192.168.233.137'

if [[ $(id -u) -ne 0 ]]; then
  echo '请使用 root 运行，例如：sudo bash grant_mcpdebian_ssh_233.sh youruser' >&2
  exit 1
fi

# If the script is invoked through sudo, authorize the original login user by default.
TARGET_USER="${1:-${SUDO_USER:-root}}"
if ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "用户不存在：$TARGET_USER（请明确指定要授权的 Linux 用户）" >&2
  exit 1
fi

# Confirm the server identity that mcpdebian observed over SSH.
if [[ -r /etc/ssh/ssh_host_ed25519_key.pub ]] && command -v ssh-keygen >/dev/null 2>&1; then
  CURRENT_FP="$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')"
  if [[ "$CURRENT_FP" != "$EXPECTED_HOST_FINGERPRINT" ]]; then
    echo "SSH 主机指纹不匹配，已停止，避免误授权到其它机器。" >&2
    echo "目标 $TARGET_IP 预期：$EXPECTED_HOST_FINGERPRINT" >&2
    echo "当前主机指纹：$CURRENT_FP" >&2
    exit 1
  fi
fi

TARGET_HOME="$(awk -F: -v name="$TARGET_USER" '$1 == name { print $6; exit }' /etc/passwd)"
if [[ -z "$TARGET_HOME" || "$TARGET_HOME" == '/' || ! -d "$TARGET_HOME" ]]; then
  echo "无法确认用户 $TARGET_USER 的 home 目录：$TARGET_HOME" >&2
  exit 1
fi

SSH_DIR="$TARGET_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
if [[ -L "$SSH_DIR" || -L "$AUTH_KEYS" ]]; then
  echo '检测到 .ssh 或 authorized_keys 为符号链接，为安全起见已停止。' >&2
  exit 1
fi

TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"
install -d -m 700 -o "$TARGET_UID" -g "$TARGET_GID" "$SSH_DIR"
if [[ ! -e "$AUTH_KEYS" ]]; then
  install -m 600 -o "$TARGET_UID" -g "$TARGET_GID" /dev/null "$AUTH_KEYS"
fi

# Keep all existing authorized keys unchanged; add this public key only once.
ENTRY="from=\"$SOURCE_IP\" $PUBKEY_TYPE $PUBKEY_DATA $KEY_COMMENT"
if grep -Fxq "$ENTRY" "$AUTH_KEYS"; then
  echo '当前授权记录已存在；跳过重复添加。'
else
  if grep -Fq "$PUBKEY_DATA" "$AUTH_KEYS"; then
    echo '提示：发现此密钥的其它授权记录，已保留原配置，请自行核实其来源限制。'
  fi
  printf '\n%s\n' "$ENTRY" >> "$AUTH_KEYS"
  echo '已添加 mcpdebian 的 SSH 公钥。'
fi

chown "$TARGET_UID:$TARGET_GID" "$SSH_DIR" "$AUTH_KEYS"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"

printf '\n授权完成：%s@%s（仅接受来源 IP %s 使用此密钥）\n' "$TARGET_USER" "$TARGET_IP" "$SOURCE_IP"
printf '从 mcpdebian 测试：\n'
printf 'ssh -i /home/devspace/.ssh/openclash_192_168_233_3 -o IdentitiesOnly=yes -o BatchMode=yes %q@%s "id && hostname"\n' "$TARGET_USER" "$TARGET_IP"
echo '未修改 sshd_config，未关闭密码登录，未重启 SSH 服务。'
