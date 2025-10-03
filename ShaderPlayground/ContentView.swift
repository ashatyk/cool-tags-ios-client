//
//  Created by ASHATYK on 03.10.2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        GeometryReader { g in
            
            let s = min(
                g.size.width / 900,
                g.size.height / 1200
            )
            
            let w = 900 * s
            let h = 1200 * s

            ZStack {
                Image("photo")
                    .resizable()
                    .frame(width: w, height: h)
                    .clipped()

                MetalView()
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)
            }
            .frame(
                width: g.size.width,
                height: g.size.height
            )
            .background(Color.black.ignoresSafeArea())
        }
    }
}


#Preview {
    ContentView()
}
