import Foundation
import NaturalLanguage

struct TextProcessor {
    
    /// 1. 潮湿的雨夜：移除所有换行，连续空白字符替换成一个空格。
    static func normalizeWhitespace(_ text: String) -> String {
        // 移除换行符
        let noNewlines = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        
        // 使用正则压缩连续空格
        let regex = try? NSRegularExpression(pattern: "\\s+", options: [])
        let range = NSRange(location: 0, length: noNewlines.utf16.count)
        let result = regex?.stringByReplacingMatches(in: noNewlines, options: [], range: range, withTemplate: " ") ?? noNewlines
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 2. 麦当劳：智能分词，然后用空格分隔每个词。
    static func tokenize(_ text: String) -> String {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            words.append(String(text[tokenRange]))
            return true
        }
        
        return words.joined(separator: " ")
    }
    
    /// 3. 音乐的诞生：智能换行，每行不超过20个字。
    static func smartWrap(_ text: String, maxChars: Int = 20) -> String {
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text
        
        var lines: [String] = []
        var currentLine = ""
        
        // 我们利用 NaturalLanguage 遍历文本块，尽量在语义边界换行
        // 但为了简单且符合“30字限制”，我们可以按字符遍历，或者稍微智能一点按词/标点
        
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let word = String(text[tokenRange])
            
            if (currentLine.count + word.count) > maxChars && !currentLine.isEmpty {
                lines.append(currentLine)
                currentLine = word
            } else {
                currentLine += word
            }
            return true
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines.joined(separator: "\n")
    }
}
