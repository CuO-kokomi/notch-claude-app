import Foundation

@MainActor
final class WeatherProvider: ObservableObject {
    @Published private(set) var temperature = "--"
    @Published private(set) var condition = "--"
    @Published private(set) var location = ""
    @Published private(set) var iconName = "cloud.fill"

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        Task {
            guard let url = URL(string: "https://wttr.in/?format=%t|%C|%l&m&lang=zh") else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("curl", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let text = String(data: data, encoding: .utf8) else { return }
            let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 2)
            if parts.count >= 3 {
                var temp = String(parts[0])
                if temp.hasPrefix("+") { temp = String(temp.dropFirst()) }
                temperature = temp
                let cond = String(parts[1]).trimmingCharacters(in: .whitespaces)
                condition = mapConditionToChinese(cond)
                let loc = String(parts[2]).trimmingCharacters(in: .whitespaces)
                location = mapCityToChinese(loc.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? loc)
                iconName = mapConditionToIcon(cond)
            }
        }
    }

    private func mapCityToChinese(_ city: String) -> String {
        let mapping: [String: String] = [
            "guangzhou": "广州", "shenzhen": "深圳", "beijing": "北京",
            "shanghai": "上海", "hangzhou": "杭州", "chengdu": "成都",
            "wuhan": "武汉", "nanjing": "南京", "tianjin": "天津",
            "chongqing": "重庆", "xian": "西安", "suzhou": "苏州",
            "dongguan": "东莞", "foshan": "佛山", "zhongshan": "中山",
            "zhuhai": "珠海", "xiamen": "厦门", "changsha": "长沙",
            "qingdao": "青岛", "dalian": "大连", "ningbo": "宁波",
            "fuzhou": "福州", "zhengzhou": "郑州", "kunming": "昆明",
            "hefei": "合肥", "jinan": "济南", "guiyang": "贵阳",
            "nanning": "南宁", "haikou": "海口", "lhasa": "拉萨",
            "urumqi": "乌鲁木齐", "lanzhou": "兰州", "xining": "西宁",
            "yinchuan": "银川", "hohhot": "呼和浩特", "harbin": "哈尔滨",
            "changchun": "长春", "shenyang": "沈阳", "taiyuan": "太原",
            "shijiazhuang": "石家庄", "nanchang": "南昌",
        ]
        return mapping[city.lowercased()] ?? city
    }

    private func mapConditionToIcon(_ condition: String) -> String {
        let lower = condition.lowercased()
        if lower.contains("晴") || lower.contains("sun") || lower.contains("clear") { return "sun.max.fill" }
        if lower.contains("多云") || lower.contains("partly") { return "cloud.sun.fill" }
        if lower.contains("阴") || lower.contains("cloud") || lower.contains("overcast") { return "cloud.fill" }
        if lower.contains("雨") || lower.contains("rain") || lower.contains("drizzle") { return "cloud.rain.fill" }
        if lower.contains("雷") || lower.contains("thunder") || lower.contains("storm") { return "cloud.bolt.fill" }
        if lower.contains("雪") || lower.contains("snow") { return "cloud.snow.fill" }
        if lower.contains("雾") || lower.contains("fog") || lower.contains("mist") { return "cloud.fog.fill" }
        if lower.contains("霾") || lower.contains("haze") { return "sun.haze.fill" }
        return "cloud.fill"
    }

    private func mapConditionToChinese(_ condition: String) -> String {
        let lower = condition.lowercased()
        if lower.contains("sunny") || lower.contains("clear") { return "晴" }
        if lower.contains("partly cloudy") { return "多云" }
        if lower.contains("overcast") { return "阴" }
        if lower.contains("cloudy") { return "多云" }
        if lower.contains("heavy rain") { return "大雨" }
        if lower.contains("light rain") || lower.contains("drizzle") || lower.contains("patchy rain") { return "小雨" }
        if lower.contains("rain") { return "雨" }
        if lower.contains("thunderstorm") || lower.contains("thunder") { return "雷阵雨" }
        if lower.contains("heavy snow") { return "大雪" }
        if lower.contains("light snow") { return "小雪" }
        if lower.contains("snow") { return "雪" }
        if lower.contains("fog") { return "雾" }
        if lower.contains("mist") { return "薄雾" }
        if lower.contains("haze") { return "霾" }
        if lower.contains("sleet") { return "雨夹雪" }
        if lower.contains("hail") { return "冰雹" }
        // Already Chinese
        if condition.contains("晴") || condition.contains("云") || condition.contains("雨") ||
           condition.contains("雪") || condition.contains("雾") || condition.contains("阴") {
            return condition
        }
        return condition
    }
}
