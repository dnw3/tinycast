import Foundation

enum CaptureToolbarItem: Codable, Hashable, Sendable {
    case annotation(CaptureAnnotation.Tool)
    case action(CaptureToolbarAction)
    case pickColor, scanCodes, addImage, suggestCovers, adjustImage, beautify, removeBackground

    static let all: [Self] = CaptureAnnotation.Tool.allCases.filter {
        ![.pixelate, .blur, .erase].contains($0)
    }.map(Self.annotation)
        + [.pickColor, .scanCodes, .addImage, .suggestCovers, .adjustImage, .beautify, .removeBackground]
        + CaptureToolbarAction.allCases.map(Self.action)
    static let standard: Set<Self> = Set<Self>([.annotation(.select), .annotation(.arrow), .annotation(.rectangle),
        .annotation(.text), .annotation(.cover)])
        .union(CaptureToolbarAction.standard.map(Self.action))

    var isAction: Bool {
        if case .action = self { return true }
        return false
    }

    var isAnnotation: Bool {
        if case .annotation = self { return true }
        return false
    }

    var toolbarEntry: Self {
        switch self {
        case .annotation(.pixelate), .annotation(.blur), .annotation(.erase): .annotation(.cover)
        default: self
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        let key: String
        if case let .annotation(tool) = self { key = tool.key } else { key = "" }
        return (title + " " + searchTerms).localizedCaseInsensitiveContains(query) || query == key
            || self == .annotation(.cover) && ["m", "f", "e"].contains(query)
    }

    private var searchTerms: String {
        switch self {
        case .annotation(.select): "选择 移动"
        case .annotation(.arrow): "箭头"
        case .annotation(.curvedArrow): "曲线 箭头"
        case .annotation(.rectangle): "矩形 方框"
        case .annotation(.ellipse): "圆形 椭圆"
        case .annotation(.text): "文字 文本"
        case .annotation(.pen): "画笔"
        case .annotation(.number): "编号 序号"
        case .annotation(.cover): "遮盖 遮挡 隐私 马赛克 像素 模糊 擦除 文字 solid pixelate blur erase text only"
        case .annotation(.pixelate): "马赛克 像素 遮挡"
        case .annotation(.crop): "裁剪"
        case .annotation(.line): "直线"
        case .annotation(.highlighter): "高亮 荧光笔"
        case .annotation(.ruler): "标尺 测量"
        case .annotation(.spotlight): "聚光灯"
        case .annotation(.blur): "模糊 遮挡"
        case .annotation(.erase): "橡皮擦 擦除 遮挡"
        case .annotation(.emoji): "表情"
        case .annotation(.magnifier): "放大镜"
        case .pickColor: "取色"
        case .scanCodes: "二维码 扫码"
        case .addImage: "添加 图片"
        case .suggestCovers: "建议 遮盖 隐私"
        case .adjustImage: "调整 图片"
        case .beautify: "美化"
        case .removeBackground: "抠图 去背景"
        case .action(.copy): "复制 cmd c"
        case .action(.save): "保存 cmd s"
        case .action(.scroll): "滚动 长截图"
        case .action(.record): "录屏 录制"
        case .action(.pin): "贴图 固定"
        case .action(.recognize): "提取 文字 OCR"
        case .action(.translate): "翻译"
        case .action(.share): "分享"
        case .action(.upload): "上传"
        }
    }

    var title: String {
        switch self {
        case .annotation(.cover): "Censor"
        case let .annotation(tool): tool.title
        case let .action(action): action.title
        case .pickColor: "Pick Color"
        case .scanCodes: "Scan QR Codes"
        case .addImage: "Add Image"
        case .suggestCovers: "Suggest Covers"
        case .adjustImage: "Adjust Image"
        case .beautify: "Beautify"
        case .removeBackground: "Remove Background"
        }
    }

    var symbol: String {
        switch self {
        case let .annotation(tool): tool.symbol
        case let .action(action): action.symbol
        case .pickColor: "eyedropper"
        case .scanCodes: "qrcode.viewfinder"
        case .addImage: "photo.badge.plus"
        case .suggestCovers: "eye.slash"
        case .adjustImage: "slider.horizontal.below.rectangle"
        case .beautify: "photo.artframe"
        case .removeBackground: "person.crop.rectangle.badge.minus"
        }
    }
}
