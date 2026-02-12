import UIKit

extension UIImage {

    /// Kompresuje obraz do zadanego rozmiaru (KB)
    /// Domyślnie ~500 KB – dobry balans jakość / wydajność
    func compressed(maxSizeKB: Int = 500) -> Data? {

        var quality: CGFloat = 0.9
        var data = jpegData(compressionQuality: quality)

        while let currentData = data,
              currentData.count > maxSizeKB * 1024,
              quality > 0.3 {

            quality -= 0.1
            data = jpegData(compressionQuality: quality)
        }

        return data
    }
}
