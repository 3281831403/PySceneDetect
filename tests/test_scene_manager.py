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

from scenedetect.backends.opencv import VideoStreamCv2
from scenedetect.common import FrameTimecode
from scenedetect.detector import FlashFilter, SceneDetector
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


class _StubDetector(SceneDetector):
    """Detector which emits no cuts itself; cuts are injected into the SceneManager directly."""

    def __init__(self, min_scene_len=0):
        super().__init__()
        self._min_scene_len = min_scene_len

    def process_frame(self, timecode, frame_img):
        return []

    @property
    def min_scene_len_filter(self) -> FlashFilter:
        return FlashFilter(mode=FlashFilter.Mode.SUPPRESS, length=self._min_scene_len)


def _make_manager_with_cuts(cut_lists, min_scene_len, fps=30.0, last_frame=999) -> SceneManager:
    """Create a SceneManager with one stub detector per entry in `cut_lists`, and the union
    of all cuts injected as if they were detected."""
    sm = SceneManager()
    for _ in cut_lists:
        sm.add_detector(_StubDetector(min_scene_len=min_scene_len))
    sm._cutting_list = [FrameTimecode(cut, fps) for cuts in cut_lists for cut in cuts]
    sm._base_timecode = FrameTimecode(0, fps)
    sm._start_pos = FrameTimecode(0, fps)
    sm._last_pos = FrameTimecode(last_frame, fps)
    return sm


def test_cut_list_multi_detector_enforces_min_scene_len():
    """Cuts merged from multiple detectors must not create intermediate scenes shorter than
    the minimum scene length."""
    # Cuts from the second detector are 15/17 frames after those of the first.
    sm = _make_manager_with_cuts([[100, 300, 500], [115, 317]], min_scene_len=18)
    cuts = [cut.frame_num for cut in sm.get_cut_list(show_warning=False)]
    assert cuts == [100, 300, 500]
    # get_scene_list must be consistent with get_cut_list.
    scene_list = sm.get_scene_list()
    assert [start.frame_num for start, _ in scene_list][1:] == cuts
    for start, end in scene_list[1:-1]:
        assert (end - start).frame_num >= 18


def test_cut_list_multi_detector_shorter_min_scene_len_keeps_cuts():
    """Cuts closer together than a larger min_scene_len are kept when the minimum is lowered."""
    sm = _make_manager_with_cuts([[100, 300, 500], [115, 317]], min_scene_len=9)
    cuts = [cut.frame_num for cut in sm.get_cut_list(show_warning=False)]
    assert cuts == [100, 115, 300, 317, 500]


def test_cut_list_multi_detector_first_and_last_scene_exempt():
    """The first and last scenes are exempt from the minimum scene length."""
    sm = _make_manager_with_cuts([[5, 100, 300], [995]], min_scene_len=18)
    cuts = [cut.frame_num for cut in sm.get_cut_list(show_warning=False)]
    assert cuts == [5, 100, 300, 995]


def test_cut_list_single_detector_unchanged():
    """With a single detector, cuts are returned exactly as detected, even if they are closer
    together than the minimum scene length."""
    sm = _make_manager_with_cuts([[100, 110, 112]], min_scene_len=18)
    cuts = [cut.frame_num for cut in sm.get_cut_list(show_warning=False)]
    assert cuts == [100, 110, 112]


def test_multi_detector_min_scene_len_end_to_end(test_video_file):
    """Multiple detectors used together must not produce intermediate scenes shorter than
    min_scene_len, while a single detector's cuts remain unchanged."""
    min_scene_len = 0.6

    def detect(detectors):
        video = VideoStreamCv2(test_video_file)
        sm = SceneManager()
        for detector in detectors:
            sm.add_detector(detector)
        sm.detect_scenes(video=video)
        cuts = [cut.frame_num for cut in sm.get_cut_list(show_warning=False)]
        scenes = sm.get_scene_list(start_in_scene=True)
        return cuts, scenes

    single_cuts, _ = detect([ContentDetector(min_scene_len=min_scene_len)])
    multi_cuts, multi_scenes = detect(
        [
            ContentDetector(min_scene_len=min_scene_len),
            ThresholdDetector(min_scene_len=min_scene_len),
            AdaptiveDetector(min_scene_len=min_scene_len),
        ]
    )
    # get_cut_list and get_scene_list must agree.
    assert [start.frame_num for start, _ in multi_scenes][1:] == multi_cuts
    # No intermediate scene shorter than the minimum scene length.
    video = VideoStreamCv2(test_video_file)
    min_frames = min_scene_len * video.frame_rate
    for start, end in multi_scenes[1:-1]:
        assert (end - start).frame_num >= min_frames
    # The single-detector result is unaffected by the multi-detector filtering.
    rerun_cuts, _ = detect([ContentDetector(min_scene_len=min_scene_len)])
    assert rerun_cuts == single_cuts
