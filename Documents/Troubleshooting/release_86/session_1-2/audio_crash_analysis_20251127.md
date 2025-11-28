Audio and Crash Analysis - November 27 2025

Two testing sessions were analyzed. Session 1 was navigation audio only from 05:06 to 05:26. Session 2 was media playback from 05:26 to 06:07 which ended in a crash.

Session 1 Findings

Navigation audio would go silent periodically despite CarPlay showing active navigation. USB disconnects occurred 72 times in 20 minutes causing DualStreamAudioManager.release() to destroy all AudioTracks. Each disconnect wiped the audio pipeline requiring full reinitialization. Siri activation or physical reconnect would temporarily restore audio by forcing clean reinit.

At 05:09:17.573 media stream stopped via platform call. At 05:09:17.604 AudioNaviStart was received and media ducked to 20 percent. At 05:09:17.904 the USB read loop stopped. At 05:09:17.920 DualStreamAudioManager released destroying all AudioTracks. The AAOS bus1_navigation_out would activate at 05:09:14.120 when nav AudioTrack was created and deactivate at 05:09:15.692 when nav track paused after stream ended.

The nav audio silence pattern was caused by AAOS deprioritizing NAVIGATION context when the nav AudioTrack entered pause state. Once AAOS deactivated bus1_navigation_out the audio routing was lost. New nav audio packets would arrive but had nowhere to play until a new AudioTrack was created. The 72 USB disconnect and reconnect cycles each triggered full audio pipeline teardown and rebuild.

Session 2 Findings

Media playback worked longer with only 20 USB disconnects in 40 minutes. Pause and resume too quickly caused silence because AAOS would disconnect bus0_media_out when AudioTrack paused. The audio buffer reached 99.99% full with 29 overflows at 05:59:10 because playback thread stopped consuming data.

Crash Sequence at 06:00

At 06:00:01.410 AAOS disconnected bus0_media_out during active playback. An AudioTrack underrun triggered at 06:00:01.510 causing the track to disable. The video decoder stalled and could not consume frames. H264Renderer buffer grew from 21 to 738 packets over 15 seconds. At 06:00:16.348 the USB read loop stopped. The CPC200-CCPA dongle was removed by the kernel at 06:00:16.359. App became unresponsive and required force close.

Root Causes

USB connection instability causes excessive audio manager releases destroying playback state. AAOS aggressively disconnects audio buses when AudioTrack enters pause or underrun state. H264Renderer has no backpressure mechanism and buffers indefinitely when decoder stalls. No recovery path exists when video buffer exceeds capacity.

Code Locations

H264Renderer.java lines 282 to 286 logs buffer warning at 20 packets but takes no protective action. DualStreamAudioManager.kt lines 441 to 474 release method destroys all tracks on any disconnect. BulkTransferHandler.kt line 330 USB read loop exit has no automatic recovery.

Additional Findings from Systematic Log Analysis

Session 1 Additional Issues

At 05:07:36.351 MediaController initialization failed with NullPointerException for CarlinkMediaBrowserService. At 05:07:43.944 USB permission denied on first open attempt causing SecurityException. Device reopened successfully after permission grant at 05:08:14.324.

Video buffer pool exhaustion occurred throughout session with POOL_CRITICAL 0/10 free appearing at 05:08:31.153 and continuing through session end. Video FPS consistently degraded to 38-41 FPS instead of target 60 FPS with warnings about OMX.Intel.hw_vd.h264 performance.

Buffer warning spikes occurred at 05:08:31 reaching 28 packets, 05:10:44 reaching 25 packets, and 05:18:56 reaching 31 packets. Each spike correlated with codec reset and USB activity.

Session 2 Additional Issues

Audio underruns accumulated throughout the session reaching 36 total. First underrun at 05:29:39.995 within 1 second of media playback starting. Underruns clustered at 05:37:07 to 05:38:04 with 9 underruns, 05:46:14 to 05:46:51 with 9 underruns, and 05:48:29 to 05:48:32 with 4 underruns.

Audio buffer overflow stuck at 66 from 05:30:07.599 through at least 05:32:41.860. The overflow counter shows written 94719 read 78720 meaning 15999 samples were lost. This overflow value remained frozen indicating a buffer state bug not actual continuous overflow.

At 05:58:57.139 AAOS disconnected bus0_media_out and reconnected at 05:58:57.709. This 570ms gap happened 2 minutes before the crash and represents the same pattern that triggered the final crash.

At 05:59:07.456 playback state changed to PLAYING. Just 29ms later at 05:59:07.485 media track was paused with stream ended message. This immediate pause after play is the core of the pause resume silence bug. The track is paused before any audio data can play.

Video buffer pool exhaustion with POOL_CRITICAL 0/12 free appeared throughout Session 2 similar to Session 1. FPS degraded to 26-44 FPS range throughout the session.

Verified Patterns Across Both Sessions

USB disconnects trigger complete audio pipeline destruction. Session 1 had 72 disconnects in 20 minutes and Session 2 had 20 disconnects in 40 minutes. The lower disconnect rate in Session 2 correlates with longer uninterrupted playback periods.

AAOS bus disconnect and reconnect cycles occur independently of USB issues. These are triggered by AudioTrack state changes particularly pause and underrun events. Each bus cycle takes 500ms to 700ms during which audio routing is lost.

Video buffer pool remains exhausted at 0 free throughout both sessions indicating buffer management issues independent of audio problems.

Media track pause within milliseconds of play start is the root cause of pause resume silence. The stream ended detection fires before audio data arrives.

Detailed 5-Minute Window Analysis of Session 1

Window 1 05:07:50 to 05:12:50

At 05:08:10.669 DualStreamAudioManager was released. At 05:08:38 Voice_Uplink setup for microphone with MIC capture thread started. At 05:08:39.120 DualStreamAudioManager initialized and Media AudioTrack created at 16000Hz mono. At 05:08:39.296 bus0_media_out was activated by HarmanHal.

At 05:09:14.064 Nav format changed from 0Hz to 44100Hz. At 05:09:14.082 NAV AudioTrack was created at 44100Hz 2ch with 28360B buffer. At 05:09:14.120 bus1_navigation_out was activated. At 05:09:14.114 Nav pre-fill completed with 65ms buffered and playback started.

At 05:09:15.589 media volume was restored to 100%. At 05:09:15.597 Nav track paused with stream ended message only 1.5 seconds after playback started. AAOS deprioritized NAVIGATION context. At 05:09:15.692 bus1_navigation_out was De-Activated. At 05:09:15.698 bus1_navigation_out disconnect completed.

At 05:10:19.626 USB device was removed at /dev/bus/usb/001/020. At 05:10:23.433 USB device reattached at /dev/bus/usb/001/021. At 05:10:24.248 Device connection closed by app. At 05:10:24.252 DualStreamAudioManager released. At 05:10:26.333 DualStreamAudioManager released again.

At 05:10:58.620 media ducked to 20%. At 05:11:03.208 media volume restored to 100%.

Window 2 05:12:50 to 05:17:50

At 05:12:32 media ducked to 20% and restored at 05:12:35. At 05:12:47 media ducked again and restored at 05:12:50.

At 05:13:08.272 DualStreamAudioManager initialized with playback thread at URGENT_AUDIO priority. At 05:13:08.288 Media format changed from 0Hz to 16000Hz. At 05:13:08.323 MEDIA AudioTrack created at 16000Hz mono with 5200B buffer. At 05:13:08.350 bus0_media_out was activated. At 05:13:08.513 Media pre-fill completed with 120ms buffered.

At 05:13:09.810 bus0_media_out was De-Activated after only 1.5 seconds. At 05:13:14.411 AudioTrack restarted after underrun with message track disabled due to previous underrun. At 05:13:14.432 bus0_media_out was re-activated.

At 05:13:16.620 media ducked to 20%. At 05:13:16.865 Nav format changed from 0Hz to 44100Hz. At 05:13:16.892 NAV AudioTrack created at 44100Hz 2ch with 28360B buffer. At 05:13:16.927 bus1_navigation_out was activated.

At 05:13:17.088 Media underrun detected with total count 2. At 05:13:17.776 media volume restored to 100%. At 05:13:17.781 Nav track paused with stream ended message. At 05:13:17.878 bus1_navigation_out was De-Activated. At 05:13:18.016 Media underrun detected with total count 3. At 05:13:19.848 bus0_media_out was De-Activated.

At 05:14:28.923 Media track paused with stream ended message. At 05:14:28.997 audio write still occurring with fill at 65ms and overflow at 0. At 05:14:29.026 bus0_media_out was De-Activated.

From 05:14:35 onwards buffer became stuck at 99.99% full with written=687039 read=599040 showing 87999 samples stuck in buffer. Overflow count climbed from 86 at 05:14:35 to 3165 at 05:17:56. Playback thread stopped consuming data after track pause triggered bus deactivation.

Window 3 05:17:50 to 05:22:50

Buffer remained stuck at 99.99% full through 05:18:26 with overflow reaching 3627.

At 05:18:32.512 Media format changed from 44100Hz to 16000Hz. At 05:18:32.685 Media pre-fill completed with 120ms buffered. At 05:18:32.847 Media track paused with stream ended only 162ms after pre-fill completed. At 05:18:32.950 bus0_media_out was De-Activated.

At 05:18:36.895 Voice_Uplink released all resources. At 05:18:36.983 DualStreamAudioManager released.

At 05:18:56.178 DualStreamAudioManager initialized. At 05:18:57.050 Media format changed from 0Hz to 44100Hz. At 05:18:57.103 bus0_media_out was activated.

At 05:19:00.224 media ducked to 20%. At 05:19:00.464 Nav format changed from 0Hz to 44100Hz. At 05:19:00.511 bus1_navigation_out was activated. At 05:19:03.486 media volume restored to 100%. At 05:19:03.489 Nav track paused with stream ended after only 3 seconds of playback. At 05:19:03.581 bus1_navigation_out was De-Activated. At 05:19:05.500 Media track paused. At 05:19:05.590 bus0_media_out was De-Activated.

Multiple USB disconnect and reconnect cycles occurred at 05:19:16 05:19:18 05:19:47 05:19:49 05:20:13 and 05:20:15 with each cycle releasing DualStreamAudioManager.

At 05:20:45.757 Media pre-fill completed with 120ms buffered. At 05:20:45.900 Media track paused only 143ms after pre-fill completed demonstrating the immediate pause after play issue.

At 05:20:53.169 Media format changed from 16000Hz to 44100Hz. At 05:20:55.586 buffer stats showed healthy state with written=read and 0 overflow. At 05:21:07.882 DualStreamAudioManager released triggering another USB disconnect cycle.

Window 4 05:22:50 to 05:25:50

At 05:22:15.613 media ducked to 20%. At 05:22:16.155 DualStreamAudioManager released.

Multiple media duck and restore cycles occurred at 05:22:34 to 05:22:37, 05:22:54 to 05:22:56, 05:23:09 to 05:23:13, 05:24:02 to 05:24:05, and 05:24:26 to 05:24:30.

Multiple USB disconnect and reconnect cycles occurred at 05:22:16 05:22:18 05:23:16 05:23:18 05:23:31 05:23:33 05:24:38 05:24:40 05:25:04 and 05:25:06 with each cycle releasing DualStreamAudioManager.

No bus1_navigation_out activity occurred in this window. Navigation audio was completely silent despite CarPlay showing active navigation.

Total DualStreamAudioManager.release() calls in Session 1 was 72 matching the documented USB disconnect count. Each release destroys all AudioTracks requiring full audio pipeline rebuild on next connection.
