# Maintainer: Jacob Enthoven <jacpa42@proton.me>

pkgname=typetest
pkgver=0.0.2
pkgrel=1
pkgdesc="Typing tool written in zig"
arch=('x86_64' 'aarch64' 'i686')
url="https://github.com/jacpa42/$pkgname"
license=('MIT')
makedepends=('git' 'zig')
source=("https://github.com/jacpa42/${pkgname}/archive/refs/tags/v${pkgver}.tar.gz")
sha256sums=('9a9395c87b3174da09c4efef538a3991a689770b2c0524017dc7ecce058fcb6b')

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
