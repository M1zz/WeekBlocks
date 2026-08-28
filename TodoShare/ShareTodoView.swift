//
//  ShareTodoView.swift
//  TodoShareExtension (macOS)
//
//  공유 창의 내용. 백로그 화면과 같은 규칙으로 그린다 —
//  작은 글씨 없이, 시간은 카드에서 쓰는 것과 똑같은 칩으로.
//
//  ⚠️ iOS의 같은 이름 파일과 짝이다. 맥에는 네비게이션 바가 없어 제목·버튼을
//     직접 얹고, Form 대신 세로 스택으로 창 크기에 맞춘다.
//

import SwiftUI

struct ShareTodoView: View {
    @Bindable var model: ShareTodoModel
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("할 일로")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                TextField("할 일", text: $model.title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .lineLimit(1...3)
                    .focused($titleFocused)

                Divider()

                if let link = model.link {
                    Label(link, systemImage: "link")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("취소") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("추가") { model.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }
        .padding(18)
        .frame(minWidth: 420, minHeight: 300)
        .overlay {
            // 받은 내용을 읽는 사이에 빈 칸이 잠깐 보이는 걸 막는다.
            if model.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            }
        }
        .onAppear { titleFocused = true }
    }
}
