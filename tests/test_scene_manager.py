#
#            PySceneDetect: Python-Based Video Scene Detector
#   -------------------------------------------------------------------
#     [  Site:    https://scenedetect.com                           ]
#     [  Docs:    https://scenedetect.com/docs/                     ]
#     [  Github:  https://github.com/Breakthrough/PySceneDetect/    ]
#
# Copyright (C) 2014 Brandon Castellano <http://www.bcastell.com>.
# PySceneDetect is licensed under the BSD 3-Clause License; see the
# included LICENSE file, or visit one of the above pages for details.
#
"""PySceneDetect scenedetect.scene_manager Tests

This file includes unit tests for the scenedetect.scene_manager.SceneManager class,
which applies SceneDetector algorithms on VideoStream backends.
"""

import pytest

from scenedetect import StatsManager, open_video
from scenedetect.backends.opencv import VideoStreamCv2
from scenedetect.common import FrameTimecode
from scenedetect.detectors import AdaptiveDetector, ContentDetector, ThresholdDetector
from scenedetect.scene_manager import SceneManager, expand_scenes_to_bounds

TEST_VIDEO_START_FRAMES_ACTUAL = [150, 180, 394]


def test_scene_list(test_video_file):
    """Test SceneManager get_scene_list method with VideoStreamCv2/ContentDetector."""
    video = VideoStreamCv2(test_video_file)
    sm = SceneManager()
    sm.add_detector(ContentDetector())

    video_fps = video.frame_rate
    start_time = FrameTimecode("00:00:05", video_fps)
    end_time = FrameTimecode("00:00:10", video_fps)

    assert end_time.frame_num > start_time.frame_num

    video.seek(start_time)
    sm.auto_downscale = True

    num_frames = sm.detect_scenes(video=video, end_time=end_time)

    assert num_frames == (end_time.frame_num - start_time.frame_num)

    scene_list = sm.get_scene_list()
    assert scene_list
    # Each scene is in the format (Start Timecode, End Timecode)
    assert len(scene_list[0]) == 2

    # First scene should start at start_time and last scene should end at end_time.
    assert scene_list[0][0] == start_time
    assert scene_list[-1][1] == end_time

    for i, _ in enumerate(scene_list):
        assert scene_list[i][0].frame_num < scene_list[i][1].frame_num
        if i > 0:
            # Ensure frame list is sorted (i.e. end time frame of
            # one scene is equal to the start time of the next).
            assert scene_list[i - 1][1] == scene_list[i][0]


def test_get_scene_list_start_in_scene(test_video_file):
    """Test SceneManager `get_scene_list()` method with the `start_in_scene` flag."""
    video = VideoStreamCv2(test_video_file)
    sm = SceneManager()
    sm.add_detector(ContentDetector())

    video_fps = video.frame_rate
    # End time must be short enough that we won't detect any scenes.
    end_time = FrameTimecode(25, video_fps)
    sm.auto_downscale = True
    sm.detect_scenes(video=video, end_time=end_time)
    # Should be an empty list.
    assert len(sm.get_scene_list()) == 0
    # Should be a list with a single element spanning the video duration.
    scene_list = sm.get_scene_list(start_in_scene=True)
    assert len(scene_list) == 1
    assert scene_list[0][0] == 0
    assert scene_list[0][1] == end_time


# TODO: This would be more readable if the callbacks were defined within the test case, e.g.
# split up the callback function and callback lambda test cases.
class FakeCallback:
    """Fake callback used for testing. Tracks the frame numbers the callback was invoked with."""

    def __init__(self):
        self.scene_list: list[int] = []

    def get_callback_lambda(self):
        """For testing using a lambda.."""
        return lambda image, frame_num: self._callback(image, frame_num)

    def get_callback_func(self):
        """For testing using a callback function."""

        def callback(image, frame_num):
            nonlocal self
            self._callback(image, frame_num)

        return callback

    def _callback(self, image, frame_num):
        self.scene_list.append(frame_num)


def test_detect_scenes_callback(test_video_file):
    """Test SceneManager detect_scenes method with a callback function.

    Note that the API signature of the callback will undergo breaking changes in v1.0.
    """
    video = VideoStreamCv2(test_video_file)
    sm = SceneManager()
    sm.add_detector(ContentDetector())

    fake_callback = FakeCallback()

    video_fps = video.frame_rate
    start_time = FrameTimecode("00:00:05", video_fps)
    end_time = FrameTimecode("00:00:15", video_fps)
    video.seek(start_time)
    sm.auto_downscale = True

    _ = sm.detect_scenes(
        video=video, end_time=end_time, callback=fake_callback.get_callback_lambda()
    )
    scene_list = sm.get_scene_list()
    assert [start for start, end in scene_list] == TEST_VIDEO_START_FRAMES_ACTUAL
    assert fake_callback.scene_list == TEST_VIDEO_START_FRAMES_ACTUAL[1:]

    # Perform same test using callback function instead of lambda.
    sm.clear()
    sm.add_detector(ContentDetector())
    fake_callback = FakeCallback()
    video.seek(start_time)

    _ = sm.detect_scenes(video=video, end_time=end_time, callback=fake_callback.get_callback_func())
    scene_list = sm.get_scene_list()
    assert [start for start, end in scene_list] == TEST_VIDEO_START_FRAMES_ACTUAL
    assert fake_callback.scene_list == TEST_VIDEO_START_FRAMES_ACTUAL[1:]


def test_detect_scenes_callback_adaptive(test_video_file):
    """Test SceneManager detect_scenes method with a callback function and a detector which
    requires frame buffering.

    Note that the API signature of the callback will undergo breaking changes in v1.0.
    """
    video = VideoStreamCv2(test_video_file)
    sm = SceneManager()
    sm.add_detector(AdaptiveDetector())

    fake_callback = FakeCallback()

    video_fps = video.frame_rate
    start_time = FrameTimecode("00:00:05", video_fps)
    end_time = FrameTimecode("00:00:15", video_fps)
    video.seek(start_time)
    sm.auto_downscale = True

    _ = sm.detect_scenes(
        video=video, end_time=end_time, callback=fake_callback.get_callback_lambda()
    )
    scene_list = sm.get_scene_list()
    assert [start for start, end in scene_list] == TEST_VIDEO_START_FRAMES_ACTUAL
    assert fake_callback.scene_list == TEST_VIDEO_START_FRAMES_ACTUAL[1:]

    # Perform same test using callback function instead of lambda.
    sm.clear()
    sm.add_detector(AdaptiveDetector())
    fake_callback = FakeCallback()
    video.seek(start_time)

    _ = sm.detect_scenes(video=video, end_time=end_time, callback=fake_callback.get_callback_func())
    scene_list = sm.get_scene_list()
    assert [start for start, end in scene_list] == TEST_VIDEO_START_FRAMES_ACTUAL
    assert fake_callback.scene_list == TEST_VIDEO_START_FRAMES_ACTUAL[1:]


def test_detect_scenes_crop(test_video_file):
    video = VideoStreamCv2(test_video_file)
    sm = SceneManager()
    sm.crop = (10, 10, 1900, 1000)
    sm.add_detector(ContentDetector())

    video_fps = video.frame_rate
    start_time = FrameTimecode("00:00:05", video_fps)
    end_time = FrameTimecode("00:00:15", video_fps)
    video.seek(start_time)
    sm.auto_downscale = True

    _ = sm.detect_scenes(video=video, end_time=end_time)
    scene_list = sm.get_scene_list()
    assert [start for start, _ in scene_list] == TEST_VIDEO_START_FRAMES_ACTUAL


def test_crop_invalid():
    sm = SceneManager()
    sm.crop = None  # type: ignore[assignment]
    sm.crop = (0, 0, 0, 0)
    sm.crop = (1, 1, 0, 0)
    sm.crop = (0, 0, 1, 1)
    with pytest.raises(TypeError):
        sm.crop = 1  # type: ignore[assignment]
    with pytest.raises(TypeError):
        sm.crop = (1, 1)  # type: ignore[assignment]
    with pytest.raises(TypeError):
        sm.crop = (1, 1, 1)  # type: ignore[assignment]
    with pytest.raises(ValueError):
        sm.crop = (1, 1, 1, -1)


def test_expand_scenes_to_bounds_two_scenes():
    """Scenes detected inside a sub-window should be extended outward."""
    fps = 10.0
    t0 = FrameTimecode(0, fps)
    t130 = FrameTimecode(130, fps)
    t150 = FrameTimecode(150, fps)
    t170 = FrameTimecode(170, fps)
    t300 = FrameTimecode(300, fps)

    scenes = [(t130, t150), (t150, t170)]
    expanded = expand_scenes_to_bounds(scenes, start=t0, end=t300)

    assert expanded == [(t0, t150), (t150, t300)]


def test_expand_scenes_to_bounds_empty():
    """Empty scene lists pass through unchanged."""
    fps = 10.0
    assert expand_scenes_to_bounds([], FrameTimecode(0, fps), FrameTimecode(100, fps)) == []


def test_expand_scenes_to_bounds_single_scene():
    """A single scene gets both endpoints extended."""
    fps = 10.0
    t0 = FrameTimecode(0, fps)
    t130 = FrameTimecode(130, fps)
    t170 = FrameTimecode(170, fps)
    t300 = FrameTimecode(300, fps)

    scenes = [(t130, t170)]
    expanded = expand_scenes_to_bounds(scenes, start=t0, end=t300)

    assert expanded == [(t0, t300)]


def test_expand_scenes_to_bounds_does_not_mutate_input():
    """The input scene list must not be modified in place."""
    fps = 10.0
    t0 = FrameTimecode(0, fps)
    t130 = FrameTimecode(130, fps)
    t150 = FrameTimecode(150, fps)
    t170 = FrameTimecode(170, fps)
    t300 = FrameTimecode(300, fps)

    scenes = [(t130, t150), (t150, t170)]
    original = list(scenes)
    expand_scenes_to_bounds(scenes, start=t0, end=t300)

    assert scenes == original


def test_detect_scenes_callback_threshold(test_fades_clip, auto_close):
    """The detect_scenes callback must fire once per cut with the cut's timecode, including
    cuts reported after their frame was evicted from the frame buffer (fade_bias < 1.0)
    and cuts supplemented by the detector's post_process (add_final_scene)."""

    def detect_with_callback(fade_bias: float) -> tuple[list[int], list[int]]:
        video = auto_close(open_video(test_fades_clip))
        sm = SceneManager()
        sm.add_detector(ThresholdDetector(fade_bias=fade_bias, add_final_scene=True))
        callback_frames = []

        def callback(image, timecode):
            assert image is not None
            callback_frames.append(timecode.frame_num)

        sm.detect_scenes(video=video, callback=callback)
        cut_frames = [cut.frame_num for cut in sm.get_cut_list(show_warning=False)]
        return callback_frames, cut_frames

    for fade_bias in (-1.0, 0.0, 1.0):
        callback_frames, cut_frames = detect_with_callback(fade_bias)
        assert cut_frames, "expected cuts to be detected on the fades test clip"
        assert callback_frames == cut_frames


def test_detect_scenes_adaptive_cut_near_end(test_video_file, auto_close):
    """A hard cut within `window_width` frames of the end of the detection window must
    still be detected by AdaptiveDetector (matching ContentDetector), and the trailing
    frames must have their adaptive_ratio metric recorded."""
    end_time = 13.2  # Truncates two frames after a hard cut.
    stats = StatsManager()
    video = auto_close(open_video(test_video_file))
    sm = SceneManager(stats_manager=stats)
    sm.add_detector(AdaptiveDetector())
    sm.detect_scenes(video=video, end_time=end_time)
    scene_list = sm.get_scene_list()
    assert [start.frame_num for start, _ in scene_list] == [0, 30, 180, 394]
    # The final scene is the two frames following the hard cut at frame 394.
    assert scene_list[-1][1].frame_num - scene_list[-1][0].frame_num == 2
    # The adaptive_ratio metric must exist for the trailing frames as well.
    metric = AdaptiveDetector.ADAPTIVE_RATIO_KEY_TEMPLATE.format(window_width=2, luma_only="")
    last_frame = video.position.frame_num
    for frame_num in (last_frame - 1, last_frame):
        assert stats.metrics_exist(FrameTimecode(frame_num, video.frame_rate), [metric])
