# Capture fixtures

`scroll.html`、`sticky.html`、`sidebar.html` 用于真实纵横长图、固定页眉/页脚和固定侧栏验收。
本地运行 `python3 -m http.server 8770 --bind 127.0.0.1 --directory Tests/Fixtures/capture`。
`make-pdf.swift` 接收一个输出路径，生成 20 页、500 个编号行的 PDF；只用于 Preview 真实滚动验收。

`nasa-portrait.jpg` 用于本地 Vision 人脸/人物候选检测与遮盖回归，不随应用打包，也不用于宣传。
来源：NASA，jsc2018e095073，2018-12-03，Christina Koch 官方肖像。

- [原页面](https://www.nasa.gov/image-article/nasa-astronaut-christina-koch/)
- [819 × 1024 图片](https://www.nasa.gov/wp-content/uploads/2023/03/jsc2018e095073_0.jpg?resize=819,1024)
- [NASA 媒体使用说明](https://www.nasa.gov/nasa-brand-center/images-and-media/)
- SHA-256：`d3363f229959b7c34b7107111d4786ec03e33be21e2df5d76d1b2d1cdcb4d07c`

Credit: NASA. This test fixture does not imply NASA or astronaut endorsement of Tinycast.
