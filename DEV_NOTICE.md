# Developer Guide

## Requirements

| Tool | Notes |
|------|-------|
| DMD or LDC2 | D compiler |
| Dub | D package manager |
| [Envman](https://github.com/kerem3338/envman) | Vendor file manager *(see below)* |

> Envman is not strictly required, but without it you will need to manage vendor files manually.

---

## What is envman?

[Envman](https://github.com/kerem3338/envman) is a file-based dependency manager. Instead of pulling in full packages, it copies individual files from a central registry directly into your project tree. For example, `tpl.d` is sourced from an upstream repository and placed at `source/dweb/tpl.d` — it is not a locally authored file.

## Dependencies
| Name       | Source Location | Target |
| ---------- | --------------- | ------ |
| template_d | https://raw.githubusercontent.com/kerem3338/dtools/refs/heads/main/template.d | source\dweb\tpl.d |

---

## Setting Up Source Dependencies

### 1. Register the dependency

```
envman pkg register template_d https://raw.githubusercontent.com/kerem3338/dtools/refs/heads/main/template.d
```

### 2. Install all dependencies

```
envman pkg install
```

### 3. Fix the module declaration

After install, open `source\dweb\tpl.d` and change the first line from:

```d
module template_d;
```

to:

```d
module dweb.tpl;
```

This is required for the project to compile correctly.
