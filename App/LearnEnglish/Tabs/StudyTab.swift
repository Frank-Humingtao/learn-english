import SwiftUI

/// 学习 tab. Card study (reviews, then new cards) arrives with ticket 07.
struct StudyTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("卡片学习即将上线", systemImage: "rectangle.on.rectangle",
                                   description: Text("先在「测试」里做一次短测，系统会据此挑选要学的词。"))
                .navigationTitle("学习")
        }
    }
}
