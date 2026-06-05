# Postme

Postme is a macOS raw HTTP repeater workspace. It lets you compose, replay, inspect, and keep a history of HTTP requests from a native SwiftUI app. The repository also includes a React/Vite product site under `postme-site`.

## Features

- Native macOS request workspace built with SwiftUI.
- Raw HTTP request editor with request normalization.
- Direct TCP/TLS transport for replaying HTTP requests.
- Response viewer with raw and formatted response content.
- Request history with status, timing, size, and errors.
- Environment variables using `$key` or `{{key}}` placeholders.
- Separate marketing/product site built with React and Tailwind CSS.

## Repository Structure

```text
.
├── Postme/              # macOS SwiftUI application source
├── Postme.xcodeproj/    # Xcode project
├── postme-site/         # React/Vite product site
└── skills-lock.json
```

## macOS App

### Requirements

- macOS with Xcode installed
- SwiftUI and Network framework support through Xcode

### Run

Open the project in Xcode:

```bash
open Postme.xcodeproj
```

Then select the `Postme` scheme and run the app.

## Product Site

The product site has its own README at `postme-site/README.md`.

### Requirements

- Bun

### Run Locally

```bash
cd postme-site
bun install
bun run dev
```

The Vite development server defaults to `http://127.0.0.1:5173/`.

### Build

```bash
cd postme-site
bun run build
```

## Development Notes

- App workspace data is persisted locally through `UserDefaults` with the `postme.workspace.v1` key.
- Request history is capped in the app store layer.
- Raw requests can use environment variables before being sent.
- The site uses Vite, React, TypeScript, Tailwind CSS v4, and shadcn/ui components.
