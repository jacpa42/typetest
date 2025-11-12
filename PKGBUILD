# Maintainer: Jacob Enthoven <jacpa42@proton.me>

pkgname=typetest
pkgver=0.0.3
pkgrel=1
pkgdesc="Typing tool written in zig"
arch=('x86_64' 'aarch64' 'i686')
url="https://github.com/jacpa42/$pkgname"
license=('MIT')
makedepends=('git' 'zig')
source=("https://github.com/jacpa42/${pkgname}/archive/refs/tags/v${pkgver}.tar.gz")
sha256sums=('246d49f55f30c32e0577ac1b5803e1da1282b429444b300599fded5089c6ccda')

build() {
    cd "$srcdir/$pkgname-${pkgver}"
    zig build -Doptimize=ReleaseFast
}

package() {
    cd "$srcdir/$pkgname-${pkgver}"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm755 "zig-out/bin/$pkgname" "$pkgdir/usr/bin/$pkgname"
}
