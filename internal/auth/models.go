package auth

import (
	"os"
	"time"
)

// LoginRequest 登录请求结构
type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// LoginResponse 登录响应结构
type LoginResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Error   string `json:"error,omitempty"`
}

// Session 用户会话结构
type Session struct {
	SessionID string    `json:"sessionId"`
	Username  string    `json:"username"`
	ExpiresAt time.Time `json:"expiresAt"`
	IsActive  bool      `json:"isActive"`
}

// SystemConfig 系统配置结构
type SystemConfig struct {
	Key         string `json:"key"`
	Value       string `json:"value"`
	Description string `json:"description,omitempty"`
}

// SystemConfigKeys 系统配置键名常量
const (
	ConfigKeyIsInitialized = "system_initialized"
	ConfigKeyAdminUsername = "admin_username"
	ConfigKeyAdminPassword = "admin_password_hash"
	ConfigKeyCurrentTokenJTI = "current_token_jti" // 当前有效的 JWT ID，用于实现 token 互踢
)

// 默认账号密码常量
const (
	DefaultAdminUsername = "nbpanel"
	DefaultAdminPassword = "Np123456"
)

// GetDefaultAdminPassword 从环境变量 NB_PANEL_ADMIN_PASSWORD 读取默认管理员密码，默认 "Np123456"
func GetDefaultAdminPassword() string {
	if pwd := os.Getenv("NB_PANEL_ADMIN_PASSWORD"); pwd != "" {
		return pwd
	}
	return DefaultAdminPassword
}
