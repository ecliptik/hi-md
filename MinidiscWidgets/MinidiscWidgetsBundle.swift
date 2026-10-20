import SwiftUI
import WidgetKit

@main
struct MinidiscWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        RecentlyPlayedWidget()
        PinnedWidget()
        MoodsWidget()
        PlayPauseControl()
        NextTrackControl()
        SmartShuffleControl()
        PlayMoodControl()
        DownloadLiveActivity()
    }
}
