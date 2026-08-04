# mkvdp – mkv duration patcher

Patches the duration metadata of MKV/WebM files in-place.

The main use case is to fool Telegram into thinking that an animated sticker is only 3 seconds long.

## Building

```bash
zig build --release=fast
```

## Usage

```
mkvdp <new duration in seconds> <mkv/webm file path>
```

### Example output

![output](assets/output.svg)
