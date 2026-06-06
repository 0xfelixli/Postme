import type { LucideIcon } from "lucide-react"
import { Braces, History, Radio, TerminalSquare } from "lucide-react"

export const capabilities: Array<{
  icon: LucideIcon
  title: string
  description: string
}> = [
  {
    icon: TerminalSquare,
    title: "直接编辑原始请求",
    description: "请求行、Header、空行和 Body 都保留为你看到的文本。",
  },
  {
    icon: Radio,
    title: "查看完整响应",
    description: "状态行、响应头、耗时、大小和正文放在同一个协议上下文里。",
  },
  {
    icon: Braces,
    title: "原始、格式化、十六进制",
    description: "需要读 JSON 时格式化，需要查字节时切到十六进制。",
  },
  {
    icon: History,
    title: "历史和变量",
    description: "常用 host 可以变量化，发过的请求可以快速回看和复用。",
  },
]

export const workflow = [
  "粘贴或写出一段原始 HTTP",
  "用变量补全 host 和 base URL",
  "发送请求并读取完整响应",
  "搜索、复制、格式化或再次发送",
]

export const shortcuts = [
  { key: "⌘ ↵", label: "发送请求" },
  { key: "⇧ ⌘ C", label: "复制请求" },
  { key: "⇧ ⌘ J", label: "格式化 JSON" },
  { key: "⇧ ⌘ L", label: "规范化 Header" },
]

export const downloadUrl =
  "https://github.com/0xfelixli/Postme/releases/latest/download/Postme.dmg"
export const releaseUrl = "https://github.com/0xfelixli/Postme/releases/tag/v1.0.1"
export const repoUrl = "https://github.com/0xfelixli/Postme"
