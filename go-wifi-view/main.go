package main

import (
	"bufio"
	"context"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime/debug"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode"
	"unsafe"

	"github.com/skip2/go-qrcode"
	"golang.org/x/image/font"
	"golang.org/x/image/font/gofont/goregular"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/fixed"
)

// ============================================================
// WiFi Password Query Tool v3.0 (Go edition)
// Single-file reimplementation of wifi_password_tool_auto.bat

// Build-time version metadata. Override via:
//   go build -ldflags "-X main.Version=v3.0.0 -X main.Commit=abc1234 -X main.BuildDate=2026-09-17"
// ============================================================
var (
	Version   = "dev"
	Commit    = "unknown"
	BuildDate = "unknown"
)

// Features: multi-language UI, netsh parsing, TXT/CSV export,
//           WiFi connect string, QR code image, query history
// ============================================================

// --- ANSI color codes ---
const (
	cReset    = "\033[0m"
	cTitle    = "\033[36m"
	cOK       = "\033[32m"
	cWarn     = "\033[33m"
	cError    = "\033[31m"
	cName     = "\033[93m"
	cPwd      = "\033[97m"
	cHint     = "\033[90m"
	cBarFill  = "\033[32m"
	cBarEmpty = "\033[90m"
)

const sep = "────────────────────────────────────────────"

// --- Multi-language netsh keywords ---
var pwdKeywords = []string{
	"Key Content", "关键内容", "キー コンテンツ", "キーコンテンツ",
	"Schlüsselinhalt", "Contenu de la clé", "Contenido de la clave",
	"Содержимое ключа", "Conteúdo da chave", "Contenuto della chiave",
	"Zawartosc klucza", "Sleutelinhoud", "키 콘텐츠", "Anahtar Içerigi",
	"Kulcstartalom", "Nyckelinnehall", "Avaimen sisalto", "Nøgleindhold",
}

var profileTypeKeywords = []string{
	"AllUserProfile", "CurrentUserProfile", "所有用户配置文件",
	"当前用户配置", "すべてのユーザープロファイル",
	"現在のユーザープロファイル", "모든사용자프로필", "현재사용자프로필",
}

// --- Language strings ---
var s map[string]string

// --- State ---
var wifiNames []string
var history []histEntry
var showPassword bool
var lastWiFiName string
var lastWiFiPassword string

const maxHistory = 10

type histEntry struct {
	name string
	pwd  string
}

// ============================================================
// Main entry point
// ============================================================
func main() {
	// Panic recovery — catch anything that escapes deeper layers so users
	// get a readable error + stack instead of a silent crash.
	defer func() {
		if r := recover(); r != nil {
			fmt.Fprintln(os.Stderr)
			fmt.Fprintf(os.Stderr, "[FATAL] 程序异常退出: %v\n", r)
			fmt.Fprintln(os.Stderr)
			fmt.Fprintln(os.Stderr, "Stack trace:")
			debug.PrintStack()
			fmt.Fprintln(os.Stderr)
			fmt.Fprintln(os.Stderr, "按任意键退出...")
			bufio.NewReader(os.Stdin).ReadString('\n')
			os.Exit(1)
		}
	}()

	enableVT()
	exec.Command("cmd", "/c", "chcp 65001 >nul").Run()

	lang := "en"
	if len(os.Args) > 1 {
		arg := strings.ToLower(os.Args[1])
		if isValidLang(arg) {
			lang = arg
		}
	} else {
		lang = detectLanguage()
	}
	loadStrings(lang)

	// Graceful shutdown on Ctrl+C / SIGTERM. Prints a friendly message and
	// exits 0; nothing else needs cleanup since we have no open files or
	// network connections to flush.
	setupSignalHandler()

	exec.Command("cmd", "/c", "title "+s["title"]).Run()

	if !checkAdmin() {
		fmt.Println()
		fmt.Println(s["err_admin"])
		fmt.Println(s["press_exit"])
		bufio.NewReader(os.Stdin).ReadString('\n')
		os.Exit(1)
	}

	clearScreen()

	for {
		showMain()
	}
}

// setupSignalHandler listens for SIGINT (Ctrl+C) and SIGTERM. On Windows,
// both map to console interrupt events. The goroutine prints a localized
// shutdown message and calls os.Exit(0); the main thread may still be
// blocked on stdin, but that's terminated by os.Exit.
func setupSignalHandler() {
	ctx, stop := signal.NotifyContext(context.Background(),
		os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		<-ctx.Done()
		fmt.Println()
		msg := "[Interrupted] exit signal received, shutting down..."
		if s != nil {
			if v, ok := s["signal_interrupt"]; ok && v != "" {
				msg = v
			}
		}
		fmt.Println(msg)
		if s != nil {
			if v, ok := s["exiting"]; ok && v != "" {
				fmt.Println(v)
			}
		}
		time.Sleep(200 * time.Millisecond)
		os.Exit(0)
	}()
}

// ============================================================
// Console helpers
// ============================================================
func enableVT() {
	kernel32 := syscall.NewLazyDLL("kernel32.dll")
	procSetMode := kernel32.NewProc("SetConsoleMode")
	procGetMode := kernel32.NewProc("GetConsoleMode")
	h := os.Stdout.Fd()
	var mode uint32
	procGetMode.Call(h, uintptr(unsafe.Pointer(&mode)))
	mode |= 0x0004
	procSetMode.Call(h, uintptr(mode))
}

func clearScreen() {
	fmt.Print("\033[2J\033[H")
}

func readLine(prompt string) string {
	fmt.Print(prompt)
	r := bufio.NewReader(os.Stdin)
	line, _ := r.ReadString('\n')
	return strings.TrimSpace(strings.TrimRight(line, "\r"))
}

func readKey(prompt string) string {
	fmt.Print(prompt)
	msvcrt := syscall.NewLazyDLL("msvcrt.dll")
	proc := msvcrt.NewProc("_getch")
	ret, _, _ := proc.Call()
	c := byte(ret)
	if c == 0 || c == 0xE0 {
		proc.Call()
	}
	return strings.ToLower(string(c))
}

func pause() {
	fmt.Print(s["press_exit"])
	bufio.NewReader(os.Stdin).ReadString('\n')
}

// ============================================================
// Language detection
// ============================================================
func isValidLang(l string) bool {
	valid := []string{"zh", "en", "ja", "ko", "de", "fr", "ru", "es",
		"it", "pt", "pl", "nl", "tr", "ar", "he", "cs", "hu", "sv", "fi", "da", "no"}
	for _, v := range valid {
		if l == v {
			return true
		}
	}
	return false
}

func detectLanguage() string {
	out, err := exec.Command("reg", "query",
		`HKCU\Control Panel\International`, "/v", "LocaleName").Output()
	if err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			if strings.Contains(line, "LocaleName") {
				fields := strings.Fields(line)
				if len(fields) >= 3 {
					loc := fields[len(fields)-1]
					if len(loc) >= 2 {
						return strings.ToLower(loc[:2])
					}
				}
			}
		}
	}
	lang := os.Getenv("LANG")
	if lang != "" && len(lang) >= 2 {
		return strings.ToLower(lang[:2])
	}
	return "en"
}

func loadStrings(lang string) {
	if lang == "zh" {
		s = map[string]string{
			"title":              "WiFi密码查询工具",
			"lang_info":          "[已自动识别: 简体中文]",
			"profiles_on_interface": "接口 WLAN 上的配置文件:",
			"group_policy":       "组策略配置文件(只读)",
			"user_profiles":      "用户配置文件",
			"none":               "无",
			"input_prompt":       "请输入序号或WiFi名称查询密码（e导出，q退出程序，/关键词模糊搜索）：",
			"query_result":       "WiFi密码查询结果",
			"searching":          "正在查找密码信息...",
			"search_no_match":    "无匹配项",
			"search_matches":     "搜索匹配",
			"search_select":      "  >> 输入序号选择 (回车返回): ",
			"search_invalid":     "无效选择，已取消",
			"wifi_name":          "WiFi名称:",
			"wifi_password":      "WiFi密码:",
			"copied":             "[密码已复制到剪贴板]",
			"menu_continue":      "继续查询其他WiFi",
			"menu_export":        "导出当前WiFi密码",
			"menu_qr":            "复制WiFi连接字符串（手机扫码）",
			"menu_qr_img":        "生成二维码图片（手机扫码连接）",
			"menu_exit":          "退出程序",
			"select_option":      "请选择操作",
			"qr_full":            "WiFi连接字符串（手机相机扫码即可连接）",
			"qr_copied":          "[连接字符串已复制到剪贴板]",
			"err_no_wifi":        cError + "[ERROR]" + cReset + " 请先查询WiFi密码！",
			"export_format_title": "请选择导出格式：",
			"format_txt":         "导出为 TXT 文本文件",
			"format_csv":         "导出为 CSV 文件",
			"format_cancel":      "取消，返回主菜单",
			"export_scope_title": "请选择导出范围：",
			"scope_all":          "导出所有 WiFi 配置",
			"scope_selected":     "导出指定编号的 WiFi 配置",
			"scope_cancel":       "取消，返回主菜单",
			"input_indices":      "请输入要导出的编号（多个用逗号分隔，如 1,3,5）：",
			"invalid_num":        "无效编号，已跳过：",
			"err_no_selection":   cError + "[ERROR]" + cReset + " 未选择有效的编号！",
			"current_selection":  "当前选择:",
			"export_title":       "批量导出WiFi密码",
			"export_filename":    "WiFi密码导出_",
			"output_file":        "导出文件路径 -",
			"processing":         "正在处理 共",
			"profiles_unit":      "个WiFi配置...",
			"export_report_title": "WiFi密码批量导出报告",
			"export_time":        "导出时间",
			"tool_version":       "导出工具",
			"total_count":        "WiFi总数",
			"col_index":          "序号",
			"col_name":           "WiFi名称",
			"col_password":       "WiFi密码",
			"no_password":        "无密码或开放网络",
			"export_stats":       "导出统计",
			"stats_success":      "成功",
			"stats_none":         "无密码",
			"stats_total":        "总计",
			"export_complete":    "导出完成！",
			"file_location":      "文件位置",
			"success_count":      "成功导出",
			"no_password_count":  "无密码",
			"signal_interrupt":   "[中断] 收到退出信号，正在优雅退出...",
			"exiting":            "正在退出WiFi密码查询工具...",
			"err_admin":          cError + "[ERROR]" + cReset + " 请以管理员身份运行此程序！",
			"press_exit":         "按任意键退出...",
			"err_no_input":       cError + "[ERROR]" + cReset + " 没有输入WiFi名称！",
			"err_not_found":      cError + "[ERROR]" + cReset + " 找不到该WiFi配置文件！",
			"err_no_password":    cError + "[ERROR]" + cReset + " 无法获取密码信息，可能是该WiFi没有保存密码。",
			"err_no_export":      cError + "[ERROR]" + cReset + " 当前没有可导出的WiFi配置！",
			"menu_toggle":        "显示/隐藏密码 (R)",
			"password_masked":    "********（已隐藏，按R切换显示）",
			"menu_history":       "查看查询历史 (H)",
			"history_title":      "查询历史记录",
			"history_empty":      "暂无查询历史",
			"history_prompt":     "输入序号可快速重新查询（q返回主菜单）：",
			"hint_bar":           "[e]导出  [h]历史  [q]退出  [/关键词]模糊搜索  [序号/名称]查询",
			"qr_img_generated":   "二维码图片已生成：",
			"qr_img_opened":      "[已自动打开图片，手机扫码即可连接WiFi]",
			"qr_img_failed":      cError + "[ERROR]" + cReset + " 二维码生成失败！",
			"qr_path_copied":     "[文件路径已复制到剪贴板]",
			"password_strength":  "密码强度:",
			"strength_empty":     "无",
			"strength_weak":     "弱",
			"strength_medium":   "中等",
			"strength_strong":   "强",
		}
	} else {
		s = map[string]string{
			"title":              "WiFi Password Query Tool",
			"lang_info":          "[Auto-detected: English]",
			"profiles_on_interface": "Profiles on interface WLAN:",
			"group_policy":       "Group policy profiles (read only)",
			"user_profiles":      "User profiles",
			"none":               "None",
			"input_prompt":       "Enter index/WiFi name to query (e=export, q=exit, /keyword fuzzy search): ",
			"query_result":       "WiFi Password Query Result",
			"searching":          "Searching for password information...",
			"search_no_match":    "No matches",
			"search_matches":     "Search matches",
			"search_select":      "  >> Pick a number (Enter to cancel): ",
			"search_invalid":     "Invalid selection, cancelled",
			"wifi_name":          "WiFi Name:",
			"wifi_password":      "WiFi Password:",
			"copied":             "[Password copied to clipboard]",
			"menu_continue":      "Query another WiFi",
			"menu_export":        "Export current WiFi password",
			"menu_qr":            "Copy WiFi connect string",
			"menu_qr_img":        "Generate QR code image (scan to connect)",
			"menu_exit":          "Exit program",
			"select_option":      "Please select an option",
			"qr_full":            "WiFi connect string (scan with phone camera to connect)",
			"qr_copied":          "[Connect string copied to clipboard]",
			"err_no_wifi":        cError + "[ERROR]" + cReset + " Please query a WiFi password first!",
			"export_format_title": "Select export format:",
			"format_txt":         "Export as TXT text file",
			"format_csv":         "Export as CSV file",
			"format_cancel":      "Cancel, back to main menu",
			"export_scope_title": "Select export scope:",
			"scope_all":          "Export all WiFi profiles",
			"scope_selected":     "Export selected WiFi profiles by index",
			"scope_cancel":       "Cancel, back to main menu",
			"input_indices":      "Enter indices to export (comma separated, e.g. 1,3,5): ",
			"invalid_num":        "Invalid index, skipped:",
			"err_no_selection":   cError + "[ERROR]" + cReset + " No valid index selected!",
			"current_selection":  "Current selection:",
			"export_title":       "Batch Export WiFi Passwords",
			"export_filename":    "WiFi_Passwords_Export_",
			"output_file":        "Output file -",
			"processing":         "Processing",
			"profiles_unit":      "WiFi profiles...",
			"export_report_title": "WiFi Password Batch Export Report",
			"export_time":        "Export Time",
			"tool_version":       "Tool Version",
			"total_count":        "Total WiFi Count",
			"col_index":          "No.",
			"col_name":           "WiFi Name",
			"col_password":       "WiFi Password",
			"no_password":        "No password or open network",
			"export_stats":       "Export Stats",
			"stats_success":      "Success",
			"stats_none":         "No Password",
			"stats_total":        "Total",
			"export_complete":    "Export complete!",
			"file_location":      "File location",
			"success_count":      "Success",
			"no_password_count":  "No password",
			"signal_interrupt":   "[Interrupted] Exit signal received, shutting down...",
			"exiting":            "Exiting WiFi Password Query Tool...",
			"err_admin":          cError + "[ERROR]" + cReset + " Please run this program as Administrator!",
			"press_exit":         "Press any key to exit...",
			"err_no_input":       cError + "[ERROR]" + cReset + " No WiFi name entered!",
			"err_not_found":      cError + "[ERROR]" + cReset + " WiFi profile not found!",
			"err_no_password":    cError + "[ERROR]" + cReset + " Unable to retrieve password. This WiFi may not have a saved password.",
			"err_no_export":      cError + "[ERROR]" + cReset + " No WiFi configurations available to export!",
			"menu_toggle":        "Show/Hide password (R)",
			"password_masked":    "******** (hidden, press R to show)",
			"menu_history":       "View query history (H)",
			"history_title":      "Query History",
			"history_empty":      "No query history yet",
			"history_prompt":     "Enter index to re-query (q=back to main): ",
			"hint_bar":           "[e]export  [h]history  [q]quit  [/keyword]fuzzy  [index/name]query",
			"qr_img_generated":   "QR code image generated: ",
			"qr_img_opened":      "[Image opened automatically, scan with phone to connect]",
			"qr_img_failed":      cError + "[ERROR]" + cReset + " QR code generation failed!",
			"qr_path_copied":     "[File path copied to clipboard]",
			"password_strength":  "Password strength:",
			"strength_empty":     "N/A",
			"strength_weak":     "Weak",
			"strength_medium":   "Medium",
			"strength_strong":   "Strong",
		}
	}
}

// ============================================================
// Admin check
// ============================================================
func checkAdmin() bool {
	c := exec.Command("net", "session")
	c.Stdout = nil
	c.Stderr = nil
	return c.Run() == nil
}

// ============================================================
// Clipboard
// ============================================================
func copyToClipboard(text string) {
	c := exec.Command("powershell", "-NoProfile", "-Command", "$input | Set-Clipboard")
	stdin, err := c.StdinPipe()
	if err != nil {
		return
	}
	c.Start()
	io.WriteString(stdin, text)
	stdin.Close()
	c.Wait()
}

// ============================================================
// WiFi profile parsing
// ============================================================
func getWiFiProfiles() []string {
	out, err := exec.Command("cmd", "/c",
		"chcp 65001 >nul & netsh wlan show profiles").Output()
	if err != nil {
		return nil
	}
	var result []string
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(strings.TrimRight(line, "\r"))
		name := parseProfileLine(line)
		if name != "" {
			result = append(result, name)
		}
	}
	return result
}

func parseProfileLine(line string) string {
	idx := strings.Index(line, ":")
	if idx < 0 {
		return ""
	}
	p1 := strings.TrimSpace(line[:idx])
	p2 := strings.TrimSpace(line[idx+1:])
	if strings.HasPrefix(p1, "<") {
		return ""
	}
	p1NoSpace := strings.ReplaceAll(p1, " ", "")
	for _, kw := range profileTypeKeywords {
		if strings.EqualFold(p1NoSpace, kw) {
			return p2
		}
	}
	lastIdx := strings.LastIndex(line, ":")
	if lastIdx < 0 {
		return ""
	}
	extracted := strings.TrimSpace(line[lastIdx+1:])
	if extracted == "" {
		return ""
	}
	isNum := p1 != ""
	for _, c := range p1 {
		if c < '0' || c > '9' {
			isNum = false
			break
		}
	}
	if !isNum {
		return extracted
	}
	if strings.Contains(p2, ":") {
		return extracted
	}
	return ""
}

// ============================================================
// WiFi password query
// ============================================================
func getWiFiPassword(name string) string {
	out, err := exec.Command("cmd", "/c",
		fmt.Sprintf("chcp 65001 >nul & netsh wlan show profile name=\"%s\" key=clear", name)).Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(strings.TrimRight(line, "\r"))
		pwd := extractPassword(line)
		if pwd != "" {
			return pwd
		}
	}
	return ""
}

func extractPassword(line string) string {
	for _, kw := range pwdKeywords {
		if strings.Contains(line, kw) {
			idx := strings.Index(line, ":")
			if idx >= 0 {
				pwd := strings.TrimSpace(line[idx+1:])
				if pwd != "" {
					return pwd
				}
			}
		}
	}
	lower := strings.ToLower(line)
	if strings.Contains(lower, "key") && strings.Contains(lower, "content") {
		idx := strings.Index(line, ":")
		if idx >= 0 {
			pwd := strings.TrimSpace(line[idx+1:])
			if pwd != "" {
				return pwd
			}
		}
	}
	return ""
}

// ============================================================
// QR string escaping
// ============================================================
func escapeQRString(str string) string {
	str = strings.ReplaceAll(str, "\\", "\\\\")
	str = strings.ReplaceAll(str, ";", "\\;")
	str = strings.ReplaceAll(str, ",", "\\,")
	str = strings.ReplaceAll(str, ":", "\\:")
	return str
}

func buildWiFiString(ssid, pwd string) string {
	return fmt.Sprintf("WIFI:T:WPA;S:%s;P:%s;;", escapeQRString(ssid), escapeQRString(pwd))
}

// ============================================================
// CSV escaping (RFC 4180)
// ============================================================
func csvEscape(field string) string {
	if !strings.Contains(field, ",") && !strings.Contains(field, "\"") {
		return field
	}
	field = strings.ReplaceAll(field, "\"", "\"\"")
	return "\"" + field + "\""
}

// ============================================================
// Progress bar
// ============================================================
func buildProgressBar(processed, total int) string {
	pct := 0
	if total > 0 {
		pct = processed * 100 / total
	}
	filled := pct / 10
	empty := 10 - filled
	bar := strings.Repeat("█", filled) + strings.Repeat("░", empty)
	return fmt.Sprintf("%s[%s]%s %d%%", cBarFill, bar, cReset, pct)
}

// ============================================================
// Query history
// ============================================================
func addHistory(name, pwd string) {
	if len(history) > 0 && strings.EqualFold(history[len(history)-1].name, name) {
		return
	}
	history = append(history, histEntry{name, pwd})
	if len(history) > maxHistory {
		history = history[len(history)-maxHistory:]
	}
}

// ============================================================
// Selection parsing
// ============================================================
func parseSelection(input string, max int) []int {
	var result []int
	for _, part := range strings.Split(input, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		n, err := strconv.Atoi(part)
		if err != nil || n < 1 || n > max {
			fmt.Printf("    %s %s\n", s["invalid_num"], part)
			continue
		}
		result = append(result, n)
	}
	return result
}

// ============================================================
// Fuzzy search WiFi profiles
// Case-insensitive substring match, multi-token AND semantics:
// "home 5g" matches "HomeWiFi-5G". Returns indices into wifiNames.
// ============================================================
func fuzzySearchWiFi(query string) []int {
	query = strings.ToLower(strings.TrimSpace(query))
	if query == "" {
		all := make([]int, len(wifiNames))
		for i := range wifiNames {
			all[i] = i
		}
		return all
	}
	tokens := strings.Fields(query)
	var matches []int
	for i, name := range wifiNames {
		lower := strings.ToLower(name)
		ok := true
		for _, t := range tokens {
			if !strings.Contains(lower, t) {
				ok = false
				break
			}
		}
		if ok {
			matches = append(matches, i)
		}
	}
	return matches
}

// ============================================================
// Main screen
// ============================================================
func showMain() {
	wifiNames = getWiFiProfiles()

	fmt.Println()
	fmt.Println(sep)
	fmt.Printf("          %s%s%s\n", cTitle, s["title"], cReset)
	fmt.Printf("          %s%s%s\n", cHint, s["lang_info"], cReset)
	fmt.Printf("          %s[v%s · %s]%s\n", cHint, Version, Commit, cReset)
	fmt.Println(sep)

	fmt.Println()
	fmt.Printf("  %s\n", s["profiles_on_interface"])
	fmt.Println()
	fmt.Printf("  [%s]\n", s["group_policy"])
	fmt.Println("  ---------------------------------")
	fmt.Printf("    <%s>\n", s["none"])
	fmt.Println()
	fmt.Printf("  [%s]\n", s["user_profiles"])
	fmt.Println("  ---------------------------------")
	if len(wifiNames) == 0 {
		fmt.Printf("    <%s>\n", s["none"])
	} else {
		for i, name := range wifiNames {
			fmt.Printf("    %02d. %s%s%s\n", i+1, cName, name, cReset)
		}
	}

	fmt.Println()
	fmt.Printf("  %s%s%s\n", cHint, s["hint_bar"], cReset)
	fmt.Println()

	input := readLine(s["input_prompt"])
	if input == "" {
		fmt.Println()
		fmt.Println(s["err_no_input"])
		time.Sleep(3 * time.Second)
		return
	}

	switch strings.ToLower(input) {
	case "q":
		fmt.Println()
		fmt.Println(s["exiting"])
		time.Sleep(2 * time.Second)
		os.Exit(0)
	case "e":
		exportAll()
		return
	case "h":
		showHistory()
		return
	}

	// Fuzzy search: "/keyword" — case-insensitive substring, multi-token AND.
	// Bare "/" with no keyword is ignored.
	if strings.HasPrefix(input, "/") {
		query := strings.TrimSpace(strings.TrimPrefix(input, "/"))
		if query != "" {
			matches := fuzzySearchWiFi(query)
			if len(matches) == 0 {
				fmt.Println()
				fmt.Printf("  %s%s%s\n", cHint, s["search_no_match"], cReset)
				time.Sleep(2 * time.Second)
				return
			}
			fmt.Println()
			fmt.Printf("  %s%s: \"%s\"%s\n", cHint, s["search_matches"], query, cReset)
			fmt.Println("  ---------------------------------")
			for i, idx := range matches {
				fmt.Printf("    %02d. %s%s%s\n", i+1, cName, wifiNames[idx], cReset)
			}
			fmt.Println("  ---------------------------------")
			sel := readLine(s["search_select"])
			n, err := strconv.Atoi(strings.TrimSpace(sel))
			if err != nil || n < 1 || n > len(matches) {
				if strings.TrimSpace(sel) != "" {
					fmt.Println(s["search_invalid"])
					time.Sleep(2 * time.Second)
				}
				return
			}
			doQuery(wifiNames[matches[n-1]])
			return
		}
	}

	var wifiName string
	if n, err := strconv.Atoi(input); err == nil && n >= 1 && n <= len(wifiNames) {
		wifiName = wifiNames[n-1]
	} else {
		wifiName = input
	}

	doQuery(wifiName)
}

// ============================================================
// Query WiFi password
// ============================================================
func doQuery(name string) {
	out, err := exec.Command("cmd", "/c",
		fmt.Sprintf("chcp 65001 >nul & netsh wlan show profile name=\"%s\"", name)).Output()
	if err != nil || strings.Contains(string(out), "not found") {
		fmt.Println()
		fmt.Println(s["err_not_found"])
		time.Sleep(3 * time.Second)
		return
	}

	fmt.Println()
	fmt.Println(sep)
	fmt.Printf("             %s%s%s\n", cTitle, s["query_result"], cReset)
	fmt.Println(sep)
	fmt.Println()
	fmt.Printf("  %s>> %s%s\n", cHint, s["searching"], cReset)
	fmt.Println()

	pwd := getWiFiPassword(name)
	if pwd == "" {
		fmt.Println(s["err_no_password"])
		time.Sleep(4 * time.Second)
		return
	}

	lastWiFiName = name
	lastWiFiPassword = pwd
	showPassword = true
	addHistory(name, pwd)
	copyToClipboard(pwd)
	displayResult()
}

// ============================================================
// Password strength scoring (0-5)
// Score components:
//   + length tier   (≥12 = +2, ≥8 = +1, <8 = -1)
//   + char classes  (3-4 types = +2, 2 types = +1)
// Penalties:
//   - common password list        (-4)
//   - contains SSID substring     (-2)
//   - sequential chars (abcd/1234) (-2)
//   - 3+ repeated chars           (-1)
// ============================================================
var commonPasswords = map[string]bool{
	"": true,
	"password": true, "passw0rd": true, "p@ssw0rd": true,
	"12345678": true, "123456789": true, "1234567890": true,
	"qwerty": true, "qwertyuiop": true, "asdfgh": true, "zxcvbn": true,
	"abc123": true, "111111": true, "1234567": true,
	"iloveyou": true, "admin": true, "welcome": true,
	"monkey": true, "letmein": true, "dragon": true, "master": true,
	"login": true, "princess": true, "football": true,
	"88888888": true, "666666": true, "woaini": true, "5201314": true,
	"a1b2c3": true, "abcd1234": true,
}

func passwordStrength(pwd, ssid string) (score int, label, color string) {
	if pwd == "" {
		return 0, s["strength_empty"], cHint
	}
	score = 0

	// Length tier
	switch {
	case len(pwd) >= 12:
		score += 2
	case len(pwd) >= 8:
		score += 1
	default:
		score -= 1
	}

	// Character classes
	classes := 0
	var hasLower, hasUpper, hasDigit, hasSpecial bool
	for _, c := range pwd {
		switch {
		case unicode.IsLower(c):
			hasLower = true
		case unicode.IsUpper(c):
			hasUpper = true
		case unicode.IsDigit(c):
			hasDigit = true
		case unicode.IsPunct(c) || unicode.IsSymbol(c):
			hasSpecial = true
		}
	}
	if hasLower {
		classes++
	}
	if hasUpper {
		classes++
	}
	if hasDigit {
		classes++
	}
	if hasSpecial {
		classes++
	}
	switch {
	case classes >= 3:
		score += 2
	case classes == 2:
		score += 1
	}

	// Penalties
	lower := strings.ToLower(pwd)
	if commonPasswords[lower] {
		score -= 4
	}
	if ssid != "" && len(ssid) >= 3 && strings.Contains(lower, strings.ToLower(ssid)) {
		score -= 2
	}
	if isSequential(pwd) {
		score -= 2
	}
	if isRepeated(pwd) {
		score -= 1
	}

	if score < 0 {
		score = 0
	}
	if score > 5 {
		score = 5
	}

	switch {
	case score <= 1:
		return score, s["strength_weak"], cError
	case score <= 3:
		return score, s["strength_medium"], cWarn
	default:
		return score, s["strength_strong"], cOK
	}
}

// isSequential returns true if the password contains a run of ≥4 chars
// that are each ±1 from the previous (ascending or descending ASCII).
func isSequential(pwd string) bool {
	if len(pwd) < 4 {
		return false
	}
	lower := strings.ToLower(pwd)
	asc, desc := 0, 0
	for i := 1; i < len(lower); i++ {
		switch int(lower[i]) - int(lower[i-1]) {
		case 1:
			asc++
			desc = 0
		case -1:
			desc++
			asc = 0
		default:
			asc, desc = 0, 0
		}
		if asc >= 3 || desc >= 3 {
			return true
		}
	}
	return false
}

// isRepeated returns true if the password has 3+ consecutive identical chars.
func isRepeated(pwd string) bool {
	if len(pwd) < 3 {
		return false
	}
	for i := 2; i < len(pwd); i++ {
		if pwd[i] == pwd[i-1] && pwd[i] == pwd[i-2] {
			return true
		}
	}
	return false
}

// buildStrengthBar renders a 5-slot bar using block chars.
// Filled slots use the strength color, empty slots use grey.
func buildStrengthBar(score, max int) string {
	if score < 0 {
		score = 0
	}
	if score > max {
		score = max
	}
	var color string
	switch {
	case score <= 1:
		color = cError
	case score <= 3:
		color = cWarn
	default:
		color = cOK
	}
	return fmt.Sprintf("%s%s%s%s%s%s",
		color, strings.Repeat("\u2588", score),
		cBarEmpty, strings.Repeat("\u2591", max-score),
		cReset, "")
}

// ============================================================
// Display query result + menu
// ============================================================
func displayResult() {
	fmt.Println()
	fmt.Println(sep)
	fmt.Printf("  %s %s%s%s\n", s["wifi_name"], cName, lastWiFiName, cReset)
	if showPassword {
		fmt.Printf("  %s %s%s%s\n", s["wifi_password"], cPwd, lastWiFiPassword, cReset)
		// Strength bar — only show when the actual password is visible.
		// If it's masked, the user can't grade what they can't see.
		score, label, color := passwordStrength(lastWiFiPassword, lastWiFiName)
		bar := buildStrengthBar(score, 5)
		fmt.Printf("  %s %s%s%s [%s]\n", s["password_strength"], color, label, cReset, bar)
	} else {
		fmt.Printf("  %s %s%s%s\n", s["wifi_password"], cHint, s["password_masked"], cReset)
	}
	fmt.Println(sep)
	fmt.Printf("  %s[OK]%s %s\n", cOK, cReset, s["copied"])

	for {
		fmt.Println()
		fmt.Println(sep)
		fmt.Printf("  1) %s\n", s["menu_continue"])
		fmt.Printf("  2) %s\n", s["menu_export"])
		fmt.Printf("  3) %s\n", s["menu_qr"])
		fmt.Printf("  4) %s\n", s["menu_qr_img"])
		fmt.Printf("  5) %s\n", s["menu_toggle"])
		fmt.Printf("  6) %s\n", s["menu_history"])
		fmt.Printf("  7) %s\n", s["menu_exit"])
		fmt.Println(sep)

		choice := readKey(fmt.Sprintf("  >> %s [1-7]: ", s["select_option"]))
		switch choice {
		case "1":
			return
		case "2":
			exportCurrent()
		case "3":
			copyWiFiString()
		case "4":
			generateQRImage()
		case "5":
			showPassword = !showPassword
			clearScreen()
			fmt.Println()
			fmt.Println(sep)
			fmt.Printf("          %s%s%s\n", cTitle, s["title"], cReset)
			fmt.Printf("          %s%s%s\n", cHint, s["lang_info"], cReset)
			fmt.Println(sep)
			displayResult()
			return
		case "6":
			showHistory()
		case "7":
			fmt.Println()
			fmt.Println(s["exiting"])
			time.Sleep(2 * time.Second)
			os.Exit(0)
		}
	}
}

// ============================================================
// Copy WiFi connect string
// ============================================================
func copyWiFiString() {
	fmt.Println()
	if lastWiFiPassword == "" {
		fmt.Println(s["err_no_wifi"])
		time.Sleep(3 * time.Second)
		return
	}
	qrStr := buildWiFiString(lastWiFiName, lastWiFiPassword)
	fmt.Println(sep)
	fmt.Printf("  %s%s%s\n", cTitle, s["qr_full"], cReset)
	fmt.Println(sep)
	fmt.Println()
	fmt.Printf("  %s%s%s\n", cPwd, qrStr, cReset)
	fmt.Println()
	fmt.Println(sep)
	copyToClipboard(qrStr)
	fmt.Printf("  %s[OK]%s %s\n", cOK, cReset, s["qr_copied"])
	fmt.Println()

	for {
		fmt.Println(sep)
		fmt.Printf("  1) %s\n", s["menu_continue"])
		fmt.Printf("  2) %s\n", s["menu_qr"])
		fmt.Printf("  3) %s\n", s["menu_exit"])
		fmt.Println(sep)
		choice := readKey(fmt.Sprintf("  >> %s [1-3]: ", s["select_option"]))
		switch choice {
		case "1":
			return
		case "2":
			copyWiFiString()
			return
		case "3":
			fmt.Println()
			fmt.Println(s["exiting"])
			time.Sleep(2 * time.Second)
			os.Exit(0)
		}
	}
}

// ============================================================
// Generate QR code image (NEW feature)
// ============================================================
func generateQRImage() {
	fmt.Println()
	if lastWiFiPassword == "" {
		fmt.Println(s["err_no_wifi"])
		time.Sleep(3 * time.Second)
		return
	}

	qrStr := buildWiFiString(lastWiFiName, lastWiFiPassword)

	// Filename: WiFi_QR_<safeSSID>_<timestamp>.png
	// Timestamp prevents accidental overwrite when generating QRs back-to-back.
	safeSSID := sanitizeFilename(lastWiFiName)
	if safeSSID == "" {
		safeSSID = "wifi"
	}
	filename := filepath.Join(getExeDir(),
		fmt.Sprintf("WiFi_QR_%s_%s.png", safeSSID, time.Now().Format("20060102_150405")))

	img, err := generateWiFiQRImage(qrStr, lastWiFiName)
	if err != nil {
		fmt.Println(s["qr_img_failed"])
		fmt.Printf("  %s\n", err)
		time.Sleep(3 * time.Second)
		return
	}

	f, err := os.Create(filename)
	if err != nil {
		fmt.Println(s["qr_img_failed"])
		fmt.Printf("  %s\n", err)
		time.Sleep(3 * time.Second)
		return
	}
	defer f.Close()
	if err := png.Encode(f, img); err != nil {
		fmt.Println(s["qr_img_failed"])
		fmt.Printf("  %s\n", err)
		time.Sleep(3 * time.Second)
		return
	}

	fmt.Println(sep)
	fmt.Printf("  %s%s%s\n", cTitle, s["menu_qr_img"], cReset)
	fmt.Println(sep)
	fmt.Println()
	fmt.Printf("  %s%s%s\n", cOK, s["qr_img_generated"], cReset)
	fmt.Printf("    %s\n", filename)
	fmt.Printf("  SSID: %s%s%s\n", cName, lastWiFiName, cReset)
	copyToClipboard(filename)
	fmt.Printf("  %s%s%s\n", cHint, s["qr_path_copied"], cReset)
	fmt.Printf("  %s%s%s\n", cHint, s["qr_img_opened"], cReset)
	fmt.Println()
	fmt.Println(sep)

	exec.Command("cmd", "/c", "start", "", filename).Run()

	for {
		fmt.Printf("  1) %s\n", s["menu_continue"])
		fmt.Printf("  2) %s\n", s["menu_qr_img"])
		fmt.Printf("  3) %s\n", s["menu_exit"])
		fmt.Println(sep)
		choice := readKey(fmt.Sprintf("  >> %s [1-3]: ", s["select_option"]))
		switch choice {
		case "1":
			return
		case "2":
			generateQRImage()
			return
		case "3":
			fmt.Println()
			fmt.Println(s["exiting"])
			time.Sleep(2 * time.Second)
			os.Exit(0)
		}
	}
}

func sanitizeFilename(name string) string {
	r := strings.NewReplacer(
		`\`, "_", `/`, "_", `:`, "_",
		`*`, "_", `?`, "_", `"`, "_",
		`<`, "_", `>`, "_", `|`, "_",
		" ", "_",
	)
	return r.Replace(name)
}

// ============================================================
// QR code with SSID label below
// ============================================================
func generateWiFiQRImage(content, ssid string) (image.Image, error) {
	q, err := qrcode.New(content, qrcode.High)
	if err != nil {
		return nil, err
	}

	const qrSize = 480
	src := q.Image(qrSize)

	const gap = 16
	const textH = 80
	totalW := qrSize
	totalH := qrSize + gap + textH

	dst := image.NewRGBA(image.Rect(0, 0, totalW, totalH))
	draw.Draw(dst, dst.Bounds(),
		&image.Uniform{C: color.White}, image.Point{}, draw.Src)
	draw.Draw(dst, image.Rect(0, 0, qrSize, qrSize),
		src, src.Bounds().Min, draw.Src)

	// Auto-fit font size so the full SSID shows without truncation
	var face font.Face
	var tw int
	for size := 36.0; size >= 14; size -= 2 {
		f, err := loadGoFont(size)
		if err != nil {
			continue
		}
		tw = int(font.MeasureString(f, ssid) >> 6)
		if tw <= totalW-32 {
			face = f
			break
		}
		f.Close()
	}
	if face == nil {
		f, err := loadGoFont(14)
		if err != nil {
			return dst, nil
		}
		face = f
		tw = int(font.MeasureString(f, ssid) >> 6)
	}
	defer face.Close()

	th := int(face.Metrics().Height >> 6)
	tx := (totalW - tw) / 2
	ty := qrSize + gap + (textH+th)/2 - 2

	d := &font.Drawer{
		Dst:  dst,
		Src:  image.NewUniform(color.Black),
		Face: face,
		Dot:  fixed.P(tx, ty),
	}
	d.DrawString(ssid)

	return dst, nil
}

func loadGoFont(size float64) (font.Face, error) {
	f, err := opentype.Parse(goregular.TTF)
	if err != nil {
		return nil, err
	}
	return opentype.NewFace(f, &opentype.FaceOptions{
		Size: size,
		DPI:  72,
	})
}

// ============================================================
// Show query history
// ============================================================
func showHistory() {
	fmt.Println()
	fmt.Println(sep)
	fmt.Printf("  %s%s%s\n", cTitle, s["history_title"], cReset)
	fmt.Println(sep)
	if len(history) == 0 {
		fmt.Printf("  %s\n", s["history_empty"])
		fmt.Println(sep)
		time.Sleep(3 * time.Second)
		return
	}
	for i, h := range history {
		fmt.Printf("  %02d. %s%s%s  [%s%s%s]\n", i+1, cName, h.name, cReset, cPwd, h.pwd, cReset)
	}
	fmt.Println(sep)
	input := readLine(s["history_prompt"])
	if strings.ToLower(input) == "q" {
		return
	}
	if n, err := strconv.Atoi(input); err == nil && n >= 1 && n <= len(history) {
		doQuery(history[n-1].name)
	}
}

// ============================================================
// Export current WiFi
// ============================================================
func exportCurrent() {
	fmt.Println()
	if lastWiFiPassword == "" {
		fmt.Println(s["err_no_wifi"])
		time.Sleep(3 * time.Second)
		return
	}
	currentIdx := 0
	for i, n := range wifiNames {
		if strings.EqualFold(n, lastWiFiName) {
			currentIdx = i + 1
			break
		}
	}
	if currentIdx == 0 {
		fmt.Println(s["err_not_found"])
		time.Sleep(3 * time.Second)
		return
	}
	selected := []int{currentIdx}
	exportFormatChoose(selected, true)
}

// ============================================================
// Export all WiFi
// ============================================================
func exportAll() {
	fmt.Println()
	fmt.Println(sep)
	fmt.Printf("     %s%s%s\n", cTitle, s["export_title"], cReset)
	fmt.Println(sep)
	if len(wifiNames) == 0 {
		fmt.Println()
		fmt.Println(s["err_no_export"])
		time.Sleep(3 * time.Second)
		return
	}

	fmt.Println()
	fmt.Println(s["export_scope_title"])
	fmt.Println(sep)
	fmt.Printf("  1) %s\n", s["scope_all"])
	fmt.Printf("  2) %s\n", s["scope_selected"])
	fmt.Printf("  0) %s\n", s["scope_cancel"])
	fmt.Println(sep)

	choice := readKey(fmt.Sprintf("  >> %s [0-2]: ", s["select_option"]))
	switch choice {
	case "0":
		return
	case "1":
		var all []int
		for i := 1; i <= len(wifiNames); i++ {
			all = append(all, i)
		}
		exportFormatChoose(all, false)
	case "2":
		input := readLine(s["input_indices"])
		if input == "" {
			fmt.Println()
			fmt.Println(s["err_no_selection"])
			time.Sleep(3 * time.Second)
			return
		}
		selected := parseSelection(input, len(wifiNames))
		if len(selected) == 0 {
			fmt.Println()
			fmt.Println(s["err_no_selection"])
			time.Sleep(3 * time.Second)
			return
		}
		exportFormatChoose(selected, false)
	}
}

// ============================================================
// Export format selection
// ============================================================
func exportFormatChoose(selected []int, isCurrent bool) {
	fmt.Println()
	if isCurrent {
		fmt.Printf("  %s %s\n", s["current_selection"], lastWiFiName)
		fmt.Println()
	}
	fmt.Println(s["export_format_title"])
	fmt.Println(sep)
	fmt.Printf("  1) %s\n", s["format_txt"])
	fmt.Printf("  2) %s\n", s["format_csv"])
	fmt.Printf("  0) %s\n", s["format_cancel"])
	fmt.Println(sep)

	choice := readKey(fmt.Sprintf("  >> %s [0-2]: ", s["select_option"]))
	switch choice {
	case "0":
		return
	case "1":
		doExport(selected, "txt")
	case "2":
		doExport(selected, "csv")
	}
}

// ============================================================
// Perform export
// ============================================================
func doExport(selected []int, format string) {
	now := time.Now()
	datestamp := now.Format("2006-01-02")
	timestamp := now.Format("15-04-05")

	ext := ".txt"
	if format == "csv" {
		ext = ".csv"
	}
	outfile := filepath.Join(getExeDir(),
		fmt.Sprintf("%s%s_%s%s", s["export_filename"], datestamp, timestamp, ext))

	total := len(selected)
	fmt.Println()
	fmt.Printf("%s %s\n", s["output_file"], outfile)
	fmt.Printf("%s %d %s\n", s["processing"], total, s["profiles_unit"])
	fmt.Println()

	exportedOK := 0
	exportedNone := 0

	var lines []string

	if format == "csv" {
		lines = append(lines, fmt.Sprintf("%s,%s,%s", s["col_index"], s["col_name"], s["col_password"]))
	} else {
		lines = append(lines, sep)
		lines = append(lines, "               "+s["export_report_title"])
		lines = append(lines, sep)
		lines = append(lines, "")
		lines = append(lines, fmt.Sprintf("%s: %s", s["export_time"], now.Format("2006-01-02 15:04:05")))
		lines = append(lines, fmt.Sprintf("%s: WiFi Password Query Tool v3.0 (Go)", s["tool_version"]))
		lines = append(lines, fmt.Sprintf("%s: %d", s["total_count"], total))
		lines = append(lines, "")
		lines = append(lines, sep)
		lines = append(lines, fmt.Sprintf("%-6s%-36s%s", s["col_index"], s["col_name"], s["col_password"]))
		lines = append(lines, sep)
	}

	for i, idx := range selected {
		name := wifiNames[idx-1]
		pwd := getWiFiPassword(name)

		bar := buildProgressBar(i+1, total)
		if pwd == "" {
			exportedNone++
			if format == "csv" {
				lines = append(lines, fmt.Sprintf("%d,%s,", idx, csvEscape(name)))
			} else {
				lines = append(lines, fmt.Sprintf("%-6d%-36s<%s>", idx, padStr(name, 36), s["no_password"]))
			}
			fmt.Printf("  %s %s  -> <%s>\n", bar, name, s["no_password"])
		} else {
			exportedOK++
			if format == "csv" {
				lines = append(lines, fmt.Sprintf("%d,%s,%s", idx, csvEscape(name), csvEscape(pwd)))
			} else {
				lines = append(lines, fmt.Sprintf("%-6d%-36s%s", idx, padStr(name, 36), pwd))
			}
			fmt.Printf("  %s %s  -> %s\n", bar, name, pwd)
		}
	}

	if format != "csv" {
		lines = append(lines, "")
		lines = append(lines, sep)
		lines = append(lines, fmt.Sprintf("%s: %s %d / %s %d / %s %d",
			s["export_stats"], s["stats_success"], exportedOK,
			s["stats_none"], exportedNone, s["stats_total"], total))
		lines = append(lines, sep)
	}

	var fileContent []byte
	if format == "csv" {
		fileContent = append([]byte{0xEF, 0xBB, 0xBF}, []byte(strings.Join(lines, "\r\n"))...)
	} else {
		fileContent = []byte(strings.Join(lines, "\r\n"))
	}
	os.WriteFile(outfile, fileContent, 0644)

	fmt.Println()
	fmt.Println(sep)
	fmt.Printf("  %s[OK]%s %s\n", cOK, cReset, s["export_complete"])
	fmt.Println(sep)
	fmt.Printf("  %s : %s\n", s["file_location"], outfile)
	fmt.Printf("  %s       : %d\n", s["success_count"], exportedOK)
	fmt.Printf("  %s   : %d\n", s["no_password_count"], exportedNone)
	fmt.Println(sep)
	fmt.Println()
	pause()
}

func padStr(s string, width int) string {
	for len([]rune(s)) < width {
		s += " "
	}
	return s
}

func getExeDir() string {
	exe, err := os.Executable()
	if err != nil {
		return "."
	}
	return filepath.Dir(exe)
}