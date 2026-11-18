import SwiftUI
import UIKit

final class BannerViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemYellow
        let label = UILabel()
        label.text = "Welcome back"
        label.font = .preferredFont(forTextStyle: .largeTitle)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

#Preview {
    BannerViewController()
}

#Preview(traits: .fixedLayout(width: 200, height: 60)) {
    let label = UILabel()
    label.text = "UIKit label"
    label.textAlignment = .center
    label.backgroundColor = .systemTeal
    return label
}
