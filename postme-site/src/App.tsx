import {
  ArrowRight,
  Braces,
  CheckCircle2,
  Code2,
  Clock3,
  Copy,
  FileText,
  History,
  Layers2,
  Monitor,
  Radio,
  Search,
  Send,
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

const features: Array<{
  icon: LucideIcon
  title: string
  description: string
}> = [
  {
    icon: TerminalSquare,
    title: "Raw HTTP first",
    description:
      "Edit the request line, headers, blank line, and body exactly as they go over the wire.",
  },
  {
    icon: Radio,
    title: "Socket-level response",
    description:
      "See status line, headers, timing, size, and body from the actual raw response stream.",
  },
  {
    icon: Braces,
    title: "Pretty, Raw, Hex",
    description:
      "Switch between complete HTTP text, readable JSON formatting, and byte-level hex output.",
  },
  {
    icon: Layers2,
    title: "Variables and history",
    description:
      "Reuse hosts and base URLs, then jump back into previous requests without rebuilding context.",
  },
]

const workflow = [
  "Write or paste a raw request",
  "Send it from a focused macOS workspace",
  "Inspect the complete HTTP response",
  "Copy, search, normalize, or replay",
]

const shortcuts = [
  { key: "⌘ ↵", label: "Send request" },
  { key: "⇧ ⌘ C", label: "Copy raw request" },
  { key: "⇧ ⌘ J", label: "Pretty print JSON body" },
  { key: "⇧ ⌘ L", label: "Normalize headers" },
]

function App() {
  return (
    <main className="min-h-screen bg-background text-foreground">
      <SiteHeader />
      <HeroSection />
      <FeatureSection />
      <WorkflowSection />
      <FooterCta />
    </main>
  )
}

function SiteHeader() {
  return (
    <header className="sticky top-0 z-40 border-b bg-background/88 backdrop-blur-xl">
      <div className="mx-auto flex h-14 w-full max-w-7xl items-center justify-between px-5 md:px-8">
        <a className="flex items-center gap-2.5" href="#top" aria-label="Postme home">
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
          <a className="transition-colors hover:text-foreground" href="#features">
            Features
          </a>
          <a className="transition-colors hover:text-foreground" href="#workflow">
            Workflow
          </a>
          <a className="transition-colors hover:text-foreground" href="#shortcuts">
            Shortcuts
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
    <section
      id="top"
      className="relative overflow-hidden border-b bg-[linear-gradient(180deg,var(--background)_0%,var(--muted)_100%)]"
    >
      <div className="mx-auto grid min-h-[calc(100svh-3.5rem)] w-full max-w-7xl items-center gap-12 px-5 py-16 md:px-8 lg:grid-cols-[0.86fr_1.14fr] lg:py-20">
        <div className="max-w-2xl">
          <Badge variant="outline" className="mb-5">
            macOS raw HTTP repeater
          </Badge>
          <h1 className="font-heading text-5xl font-semibold tracking-tight text-balance md:text-7xl">
            Inspect HTTP like a request actually happened.
          </h1>
          <p className="mt-6 max-w-xl text-lg leading-8 text-muted-foreground">
            Postme is a focused macOS workspace for sending raw HTTP requests,
            replaying them quickly, and reading the full response without
            hiding the protocol details.
          </p>

          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            <Button asChild size="lg">
              <a href="https://github.com/0xfelixli/Postme">
                View on GitHub
                <ArrowRight data-icon="inline-end" />
              </a>
            </Button>
            <Button asChild size="lg" variant="outline">
              <a href="#features">
                Explore features
              </a>
            </Button>
          </div>

          <div className="mt-10 grid max-w-lg grid-cols-3 gap-4 text-sm">
            <Metric value="Raw" label="request editing" />
            <Metric value="3" label="response modes" />
            <Metric value="100" label="history entries" />
          </div>
        </div>

        <ProductMock />
      </div>
    </section>
  )
}

function Metric({ value, label }: { value: string; label: string }) {
  return (
    <div className="border-l pl-4">
      <div className="font-heading text-2xl font-semibold tracking-tight">
        {value}
      </div>
      <div className="mt-1 text-muted-foreground">{label}</div>
    </div>
  )
}

function ProductMock() {
  return (
    <div className="relative mx-auto w-full max-w-3xl">
      <div className="absolute -inset-x-3 -bottom-5 h-16 rounded-[100%] bg-foreground/10 blur-2xl" />
      <div className="relative overflow-hidden rounded-2xl border bg-card shadow-2xl shadow-foreground/12">
        <div className="flex h-11 items-center gap-2 border-b bg-muted/60 px-4">
          <span className="size-3 rounded-full bg-destructive" />
          <span className="size-3 rounded-full bg-[oklch(0.78_0.17_82)]" />
          <span className="size-3 rounded-full bg-[oklch(0.68_0.18_145)]" />
          <div className="ml-2 text-sm font-medium">Postme</div>
        </div>

        <div className="grid min-h-[480px] grid-cols-[190px_1fr] bg-background md:grid-cols-[230px_1fr]">
          <aside className="border-r bg-muted/45 p-3">
            <div className="mb-3 flex items-center justify-between">
              <span className="text-xs font-medium text-muted-foreground">
                Requests
              </span>
              <Badge variant="secondary">8</Badge>
            </div>
            <div className="flex flex-col gap-2">
              {["GET /posts/1", "POST /login", "GET $baseUrl/users"].map(
                (item, index) => (
                  <div
                    className={
                      index === 0
                        ? "rounded-lg bg-primary p-2 text-primary-foreground"
                        : "rounded-lg border bg-background p-2"
                    }
                    key={item}
                  >
                    <div className="flex items-center gap-2 text-xs font-semibold">
                      <span
                        className={
                          index === 0
                            ? "rounded bg-primary-foreground/18 px-1.5 py-0.5"
                            : "rounded bg-primary/10 px-1.5 py-0.5 text-primary"
                        }
                      >
                        GET
                      </span>
                      <span className="truncate">{item}</span>
                    </div>
                    <div
                      className={
                        index === 0
                          ? "mt-1 truncate text-xs text-primary-foreground/70"
                          : "mt-1 truncate text-xs text-muted-foreground"
                      }
                    >
                      jsonplaceholder.typicode.com
                    </div>
                  </div>
                )
              )}
            </div>
          </aside>

          <div className="flex min-w-0 flex-col">
            <div className="border-b bg-muted/25 p-3">
              <div className="flex items-center gap-2">
                <div className="min-w-0 flex-1 rounded-lg border bg-background px-3 py-2 text-sm font-semibold">
                  GET /posts/1
                </div>
                <Badge variant="secondary">HTTPS</Badge>
                <Button size="sm">
                  <Send data-icon="inline-start" />
                  Send
                </Button>
              </div>
            </div>

            <div className="grid flex-1 grid-cols-1 lg:grid-cols-2">
              <MockPane
                title="Request"
                icon={FileText}
                lines={[
                  "GET /posts/1 HTTP/1.1",
                  "Host: jsonplaceholder.typicode.com",
                  "Accept: application/json",
                  "Connection: close",
                ]}
              />
              <MockPane
                title="Raw response"
                icon={CheckCircle2}
                lines={[
                  "HTTP/1.1 200 OK",
                  "Content-Type: application/json; charset=utf-8",
                  "x-powered-by: Express",
                  "",
                  "{",
                  '  "userId": 1,',
                  '  "id": 1,',
                  '  "title": "sunt aut facere",',
                  '  "body": "quia et suscipit\\n..."',
                  "}",
                ]}
                response
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function MockPane({
  title,
  icon: Icon,
  lines,
  response = false,
}: {
  title: string
  icon: LucideIcon
  lines: string[]
  response?: boolean
}) {
  return (
    <section className="min-w-0 border-r last:border-r-0">
      <div className="flex items-center justify-between border-b px-4 py-3">
        <div className="flex items-center gap-2">
          <Icon className="size-4 text-primary" aria-hidden="true" />
          <span className="text-sm font-semibold">{title}</span>
        </div>
        {response ? <Badge variant="outline">200 OK</Badge> : null}
      </div>
      <pre className="min-h-[320px] overflow-hidden p-4 font-mono text-[12px] leading-6 text-muted-foreground">
        {lines.map((line, index) => (
          <code className="block bg-transparent p-0" key={`${line}-${index}`}>
            <span className="mr-4 inline-block w-5 text-right text-muted-foreground/55">
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

function FeatureSection() {
  return (
    <section id="features" className="border-b px-5 py-20 md:px-8">
      <div className="mx-auto max-w-7xl">
        <div className="max-w-2xl">
          <h2 className="font-heading text-4xl font-semibold tracking-tight md:text-5xl">
            Built for repeatable protocol work.
          </h2>
          <p className="mt-4 text-lg leading-8 text-muted-foreground">
            Postme keeps the workspace quiet and direct so the raw request,
            response, and debugging loop stay visible.
          </p>
        </div>

        <div className="mt-10 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {features.map((feature) => (
            <Card key={feature.title} className="bg-card/70">
              <CardHeader>
                <feature.icon
                  className="mb-3 size-5 text-primary"
                  aria-hidden="true"
                />
                <CardTitle>{feature.title}</CardTitle>
                <CardDescription>{feature.description}</CardDescription>
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
    <section id="workflow" className="border-b bg-muted/35 px-5 py-20 md:px-8">
      <div className="mx-auto grid max-w-7xl gap-10 lg:grid-cols-[0.9fr_1.1fr]">
        <div>
          <Badge variant="secondary">Workflow</Badge>
          <h2 className="mt-4 font-heading text-4xl font-semibold tracking-tight md:text-5xl">
            Fast enough for replay, detailed enough for debugging.
          </h2>
          <p className="mt-4 text-lg leading-8 text-muted-foreground">
            Use Postme when a browser client or high-level API tool hides the
            exact bytes you need to inspect.
          </p>
        </div>

        <div className="grid gap-4">
          {workflow.map((item, index) => (
            <div
              className="flex items-center gap-4 rounded-xl border bg-background p-4"
              key={item}
            >
              <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary text-sm font-semibold text-primary-foreground">
                {index + 1}
              </div>
              <div className="font-medium">{item}</div>
            </div>
          ))}
        </div>
      </div>

      <div
        id="shortcuts"
        className="mx-auto mt-12 grid max-w-7xl gap-4 md:grid-cols-4"
      >
        {shortcuts.map((shortcut) => (
          <Card size="sm" key={shortcut.key}>
            <CardContent className="flex items-center justify-between gap-4">
              <kbd className="rounded-md border bg-muted px-2 py-1 font-mono text-xs">
                {shortcut.key}
              </kbd>
              <span className="text-sm text-muted-foreground">
                {shortcut.label}
              </span>
            </CardContent>
          </Card>
        ))}
      </div>
    </section>
  )
}

function FooterCta() {
  return (
    <footer className="px-5 py-16 md:px-8">
      <div className="mx-auto flex max-w-7xl flex-col gap-8 md:flex-row md:items-center md:justify-between">
        <div className="max-w-2xl">
          <div className="mb-4 flex items-center gap-3">
            <img src="/postme-icon.png" alt="" className="size-10 rounded-xl" />
            <div className="font-heading text-lg font-semibold">Postme</div>
          </div>
          <h2 className="font-heading text-3xl font-semibold tracking-tight">
            A small, sharp HTTP repeater for macOS.
          </h2>
          <p className="mt-3 text-muted-foreground">
            Open source, focused, and built around the raw HTTP workflow.
          </p>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row">
          <Button asChild>
            <a href="https://github.com/0xfelixli/Postme">
              <Code2 data-icon="inline-start" />
              View repository
            </a>
          </Button>
          <Button asChild variant="outline">
            <a href="#top">
              Back to top
              <ArrowRight data-icon="inline-end" />
            </a>
          </Button>
        </div>
      </div>

      <Separator className="mx-auto my-10 max-w-7xl" />

      <div className="mx-auto flex max-w-7xl flex-wrap items-center gap-x-6 gap-y-3 text-sm text-muted-foreground">
        <span className="inline-flex items-center gap-2">
          <Monitor className="size-4" aria-hidden="true" />
          macOS app
        </span>
        <span className="inline-flex items-center gap-2">
          <ShieldCheck className="size-4" aria-hidden="true" />
          Raw request control
        </span>
        <span className="inline-flex items-center gap-2">
          <Clock3 className="size-4" aria-hidden="true" />
          Request history
        </span>
        <span className="inline-flex items-center gap-2">
          <Search className="size-4" aria-hidden="true" />
          Response search
        </span>
        <span className="inline-flex items-center gap-2">
          <History className="size-4" aria-hidden="true" />
          Replay workflow
        </span>
        <span className="inline-flex items-center gap-2">
          <Copy className="size-4" aria-hidden="true" />
          Copy exact output
        </span>
      </div>
    </footer>
  )
}

export default App
