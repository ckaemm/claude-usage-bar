// Yalnızca Command Line Tools kurulu makinelerde `swift test`in Swift Testing yardımcı aracı
// testleri keşfedemeyebiliyor. Bu küçük çalıştırıcı test paketini yükleyip Swift Testing'i doğrudan başlatır.
// Kullanım: ./test.sh
import Foundation
@_spi(ForToolsIntegrationOnly) import Testing

@main struct TestRunner {
    static func main() async {
        let path = CommandLine.arguments[1]
        guard dlopen(path, RTLD_NOW) != nil else {
            FileHandle.standardError.write(Data("dlopen başarısız: \(String(cString: dlerror()))\n".utf8))
            exit(2)
        }
        let code: CInt = await Testing.__swiftPMEntryPoint(passing: nil)
        exit(code)
    }
}
