import {
  ArrowRight,
  Braces,
  CheckCircle2,
  Clock3,
  Code2,
  Copy,
  FileText,
  History,
  Monitor,
  Radio,
  Search,
  ShieldCheck,
  TerminalSquare,
  type LucideIcon,
} from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Separator } from "@/components/ui/separator"

const capabilities: Array<{
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

const workflow = [
  "粘贴或写出一段原始 HTTP",
  "用变量补全 host 和 base URL",
  "发送请求并读取完整响应",
  "搜索、复制、格式化或再次发送",
]

const shortcuts = [
  { key: "⌘ ↵", label: "发送请求" },
  { key: "⇧ ⌘ C", label: "复制请求" },
  { key: "⇧ ⌘ J", label: "格式化 JSON" },
  { key: "⇧ ⌘ L", label: "规范化 Header" },
]

function App() {
  return (
    <main className="min-h-[100dvh] bg-background text-foreground">
      <SiteHeader />
      <HeroSection />
      <ProtocolSection />
      <CapabilitySection />
      <WorkflowSection />
      <FooterCta />
    </main>
  )
}

function SiteHeader() {
  return (
    <header className="sticky top-0 z-40 border-b bg-background/90 backdrop-blur-xl">
      <div className="mx-auto flex h-14 w-full max-w-7xl items-center justify-between px-5 md:px-8">
        <a className="flex items-center gap-2.5" href="#top" aria-label="Postme 首页">
          <img
            src="/postme-icon.png"
            alt=""
            className="size-8 rounded-lg shadow-sm"
          />
          <span className="font-heading text-sm font-semibold tracking-tight">
            Postme
          </span>
        </a>

        <nav className="hidden items-center gap-6 text-sm text-muted-foreground md:flex">
          <a className="transition-colors hover:text-foreground" href="#protocol">
            协议视图
          </a>
          <a className="transition-colors hover:text-foreground" href="#capabilities">
            能力
          </a>
          <a className="transition-colors hover:text-foreground" href="#workflow">
            工作流
          </a>
        </nav>

        <Button asChild size="sm" variant="outline">
          <a href="https://github.com/0xfelixli/Postme">
            <Code2 data-icon="inline-start" />
            GitHub
          </a>
        </Button>
      </div>
    </header>
  )
}

function HeroSection() {
  return (
    <section id="top" className="border-b">
      <div className="mx-auto grid min-h-[calc(100dvh-3.5rem)] w-full max-w-7xl items-center gap-12 px-5 py-14 md:px-8 lg:grid-cols-[0.95fr_1.05fr]">
        <div className="max-w-2xl">
          <div className="mb-6 flex items-center gap-3">
            <img src="/postme-icon.png" alt="" className="size-12 rounded-xl" />
            <Badge variant="outline">macOS 原始 HTTP 重放器</Badge>
          </div>

          <h1 className="font-heading text-4xl font-semibold leading-tight tracking-tight text-balance md:text-6xl">
            把 HTTP 请求按真实的样子发出去。
          </h1>

          <p className="mt-5 max-w-xl text-lg leading-8 text-muted-foreground">
            Postme 是一个轻量的 macOS 工具，用原始 HTTP 编辑、发送、复看响应。
          </p>

          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            <Button asChild size="lg">
              <a href="https://github.com/0xfelixli/Postme">
                查看源码
                <ArrowRight data-icon="inline-end" />
              </a>
            </Button>
            <Button asChild size="lg" variant="outline">
              <a href="#protocol">看协议视图</a>
            </Button>
          </div>
        </div>

        <ProtocolDeck />
      </div>
    </section>
  )
}

function ProtocolDeck() {
  return (
    <div className="relative mx-auto w-full max-w-2xl">
      <div className="rounded-2xl border bg-card p-3 shadow-xl shadow-primary/10">
        <div className="mb-3 flex items-center justify-between rounded-xl border bg-muted/45 px-3 py-2">
          <div className="flex items-center gap-2">
            <span className="size-2.5 rounded-full bg-destructive" />
            <span className="size-2.5 rounded-full bg-[oklch(0.76_0.15_85)]" />
            <span className="size-2.5 rounded-full bg-[oklch(0.66_0.15_150)]" />
          </div>
          <div className="font-mono text-xs text-muted-foreground">
            GET /posts/1
          </div>
        </div>

        <div className="grid gap-3 md:grid-cols-[0.92fr_1.08fr]">
          <ProtocolPanel
            title="请求"
            icon={FileText}
            tone="default"
            lines={[
              "GET /posts/1 HTTP/1.1",
              "Host: jsonplaceholder.typicode.com",
              "Accept: application/json",
              "Connection: close",
            ]}
          />
          <ProtocolPanel
            title="响应"
            icon={CheckCircle2}
            tone="success"
            lines={[
              "HTTP/1.1 200 OK",
              "Content-Type: application/json",
              "x-powered-by: Express",
              "",
              "{",
              '  "id": 1,',
              '  "title": "sunt aut facere",',
              '  "body": "quia et suscipit\\n..."',
              "}",
            ]}
          />
        </div>

        <div className="mt-3 grid gap-3 text-sm sm:grid-cols-3">
          <StatusTile label="耗时" value="679 ms" />
          <StatusTile label="大小" value="1 KB" />
          <StatusTile label="模式" value="原始" />
        </div>
      </div>
    </div>
  )
}

function ProtocolPanel({
  title,
  icon: Icon,
  lines,
  tone,
}: {
  title: string
  icon: LucideIcon
  lines: string[]
  tone: "default" | "success"
}) {
  return (
    <section className="overflow-hidden rounded-xl border bg-background">
      <div className="flex items-center justify-between border-b px-3 py-2">
        <div className="flex items-center gap-2 text-sm font-medium">
          <Icon
            className={tone === "success" ? "size-4 text-primary" : "size-4"}
            aria-hidden="true"
          />
          {title}
        </div>
        {tone === "success" ? <Badge variant="secondary">200 OK</Badge> : null}
      </div>
      <pre className="min-h-64 overflow-hidden p-3 font-mono text-[12px] leading-6 text-muted-foreground">
        {lines.map((line, index) => (
          <code className="block bg-transparent p-0" key={`${line}-${index}`}>
            <span className="mr-3 inline-block w-5 text-right text-muted-foreground/55">
              {index + 1}
            </span>
            <span className={line.startsWith("HTTP/") ? "text-primary" : ""}>
              {line || " "}
            </span>
          </code>
        ))}
      </pre>
    </section>
  )
}

function StatusTile({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border bg-background px-3 py-2">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="mt-1 font-mono text-sm font-medium">{value}</div>
    </div>
  )
}

function ProtocolSection() {
  return (
    <section id="protocol" className="border-b px-5 py-18 md:px-8 md:py-24">
      <div className="mx-auto grid max-w-7xl gap-8 lg:grid-cols-[0.78fr_1.22fr]">
        <div className="max-w-xl">
          <h2 className="font-heading text-3xl font-semibold tracking-tight md:text-5xl">
            请求和响应并排，少一点猜测。
          </h2>
          <p className="mt-4 text-lg leading-8 text-muted-foreground">
            你可以直接看到请求文本、响应头、正文、耗时和体积，不需要在多个面板里找线索。
          </p>
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <InfoBlock title="原始 HTTP" text="保留协议文本，不把请求拆成表单。" />
          <InfoBlock title="格式化 JSON" text="正文可读，字符串里的换行也能展开。" />
          <InfoBlock title="十六进制" text="需要排查编码或字节时，不离开工具。" />
          <InfoBlock title="搜索" text="响应很长时，只看命中的行。" />
        </div>
      </div>
    </section>
  )
}

function InfoBlock({ title, text }: { title: string; text: string }) {
  return (
    <Card className="bg-card/72">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{text}</CardDescription>
      </CardHeader>
    </Card>
  )
}

function CapabilitySection() {
  return (
    <section id="capabilities" className="border-b bg-muted/30 px-5 py-18 md:px-8 md:py-24">
      <div className="mx-auto max-w-7xl">
        <h2 className="max-w-2xl font-heading text-3xl font-semibold tracking-tight md:text-5xl">
          为调试循环做减法。
        </h2>

        <div className="mt-10 grid gap-4 md:grid-cols-6">
          {capabilities.map((item, index) => (
            <Card
              className={
                index === 0 || index === 3
                  ? "md:col-span-3"
                  : "md:col-span-2"
              }
              key={item.title}
            >
              <CardHeader>
                <item.icon className="mb-3 size-5 text-primary" aria-hidden="true" />
                <CardTitle>{item.title}</CardTitle>
                <CardDescription>{item.description}</CardDescription>
              </CardHeader>
            </Card>
          ))}
        </div>
      </div>
    </section>
  )
}

function WorkflowSection() {
  return (
    <section id="workflow" className="border-b px-5 py-18 md:px-8 md:py-24">
      <div className="mx-auto grid max-w-7xl gap-10 lg:grid-cols-[1fr_1fr]">
        <div>
          <h2 className="font-heading text-3xl font-semibold tracking-tight md:text-5xl">
            从粘贴请求到再次发送，路径要短。
          </h2>
          <div className="mt-8 grid gap-3">
            {workflow.map((item) => (
              <div className="rounded-xl border bg-card px-4 py-3 font-medium" key={item}>
                {item}
              </div>
            ))}
          </div>
        </div>

        <Card className="self-start">
          <CardHeader>
            <CardTitle>快捷键</CardTitle>
            <CardDescription>
              常用动作放在键盘上，适合反复试请求。
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-3">
            {shortcuts.map((shortcut) => (
              <div className="flex items-center justify-between gap-4" key={shortcut.key}>
                <kbd className="rounded-md border bg-muted px-2 py-1 font-mono text-xs">
                  {shortcut.key}
                </kbd>
                <span className="text-sm text-muted-foreground">
                  {shortcut.label}
                </span>
              </div>
            ))}
          </CardContent>
        </Card>
      </div>
    </section>
  )
}

function FooterCta() {
  return (
    <footer className="px-5 py-14 md:px-8">
      <div className="mx-auto max-w-7xl">
        <div className="flex flex-col gap-8 md:flex-row md:items-end md:justify-between">
          <div className="max-w-2xl">
            <div className="mb-4 flex items-center gap-3">
              <img src="/postme-icon.png" alt="" className="size-10 rounded-xl" />
              <div className="font-heading text-lg font-semibold">Postme</div>
            </div>
            <h2 className="font-heading text-3xl font-semibold tracking-tight">
              一个更贴近协议本身的 macOS HTTP 重放器。
            </h2>
          </div>

          <Button asChild>
            <a href="https://github.com/0xfelixli/Postme">
              <Code2 data-icon="inline-start" />
              查看源码
            </a>
          </Button>
        </div>

        <Separator className="my-10" />

        <div className="flex flex-wrap items-center gap-x-6 gap-y-3 text-sm text-muted-foreground">
          <span className="inline-flex items-center gap-2">
            <Monitor className="size-4" aria-hidden="true" />
            macOS
          </span>
          <span className="inline-flex items-center gap-2">
            <ShieldCheck className="size-4" aria-hidden="true" />
            原始请求
          </span>
          <span className="inline-flex items-center gap-2">
            <Clock3 className="size-4" aria-hidden="true" />
            历史
          </span>
          <span className="inline-flex items-center gap-2">
            <Search className="size-4" aria-hidden="true" />
            搜索
          </span>
          <span className="inline-flex items-center gap-2">
            <Copy className="size-4" aria-hidden="true" />
            复制
          </span>
        </div>
      </div>
    </footer>
  )
}

export default App
