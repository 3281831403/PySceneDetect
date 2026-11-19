#
#            PySceneDetect: Python-Based Video Scene Detector
#   -------------------------------------------------------------------
#     [  Site:    https://scenedetect.com                           ]
#     [  Docs:    https://scenedetect.com/docs/                     ]
#     [  Github:  https://github.com/Breakthrough/PySceneDetect/    ]
#
# Copyright (C) 2021 Brandon Castellano <http://www.bcastell.com>.
# PySceneDetect is licensed under the BSD 3-Clause License; see the
# included LICENSE file, or visit one of the above pages for details.
#
""":class:`AdaptiveDetector` compares the difference in content between adjacent frames similar
to `ContentDetector` except the threshold isn't fixed, but is a rolling average of adjacent frame
changes. This can help mitigate false detections in situations such as fast camera motions.

This detector is available from the command-line as the `detect-adaptive` command.
"""

from logging import getLogger

import numpy as np

from scenedetect.common import FrameTimecode, TimecodeLike
from scenedetect.detectors import ContentDetector

logger = getLogger("pyscenedetect")


class AdaptiveDetector(ContentDetector):
    """Two-pass detector that calculates frame scores with ContentDetector, and then applies
    a rolling average when processing the result that can help mitigate false detections
    in situations such as camera movement.
    """

    ADAPTIVE_RATIO_KEY_TEMPLATE = "adaptive_ratio{luma_only} (w={window_width})"

    def __init__(
        self,
        adaptive_threshold: float = 3.0,
        min_scene_len: TimecodeLike = 15,
        window_width: int = 2,
        min_content_val: float = 15.0,
        weights: ContentDetector.Components = ContentDetector.DEFAULT_COMPONENT_WEIGHTS,
        luma_only: bool = False,
        kernel_size: int | None = None,
    ):
        """
        Arguments:
            adaptive_threshold: Threshold (float) that score ratio must exceed to trigger a
                new scene (see frame metric adaptive_ratio in stats file).
            min_scene_len: Once a cut is detected, this much time must pass before a new one can
                be added to the scene list. Accepts an int (frames), float (seconds), or
                str (e.g. ``"0.6s"``, ``"00:00:00.600"``).
            window_width: Size of window (number of frames) before and after each frame to
                average together in order to detect deviations from the mean. Must be at least 1.
            min_content_val: Minimum threshold (float) that the content_val must exceed in order to
                register as a new scene. This is calculated the same way that `detect-content`
                calculates frame score based on `weights`/`luma_only`/`kernel_size`.
            weights: Weight to place on each component when calculating frame score
                (`content_val` in a statsfile, the value `threshold` is compared against).
                If omitted, the default ContentDetector weights are used.
            luma_only: If True, only considers changes in the luminance channel of the video.
                Equivalent to specifying `weights` as
                :attr:`~scenedetect.detectors.content_detector.ContentDetector.LUMA_ONLY_WEIGHTS`.
                Overrides `weights` if both are set.
            kernel_size: Size of kernel to use for post edge detection filtering. If None,
                automatically set based on video resolution.
        """
        if window_width < 1:
            raise ValueError("window_width must be at least 1.")

        super().__init__(
            threshold=255.0,
            min_scene_len=0,
            weights=weights,
            luma_only=luma_only,
            kernel_size=kernel_size,
        )

        # TODO: Turn these public options into properties.
        self.min_scene_len = min_scene_len
        self.adaptive_threshold = adaptive_threshold
        self.min_content_val = min_content_val
        self.window_width = window_width

        self._adaptive_ratio_key = AdaptiveDetector.ADAPTIVE_RATIO_KEY_TEMPLATE.format(
            window_width=window_width, luma_only="" if not luma_only else "_lum"
        )
        self._buffer: list[tuple[FrameTimecode, float]] = []
        # NOTE: The name of last cut is different from `self._last_scene_cut` from our base class,
        # and serves a different purpose!
        self._last_cut: FrameTimecode | None = None

    @property
    def event_buffer_length(self) -> int:
        return self.window_width

    def get_metrics(self) -> list[str]:
        return [*super().get_metrics(), self._adaptive_ratio_key]

    def process_frame(self, timecode: FrameTimecode, frame_img: np.ndarray) -> list[FrameTimecode]:
        super().process_frame(timecode=timecode, frame_img=frame_img)

        # If the parent could not calculate a frame score, there's nothing to buffer.
        if self._frame_score is None:
            return []

        # Initialize last scene cut point at the beginning of the frames of interest.
        if self._last_cut is None:
            self._last_cut = timecode

        required_frames = 1 + (2 * self.window_width)
        self._buffer.append((timecode, self._frame_score))
        if not len(self._buffer) >= required_frames:
            return []
        self._buffer = self._buffer[-required_frames:]
        (target_timecode, target_score) = self._buffer[self.window_width]
        adaptive_ratio = self._compute_adaptive_ratio(self._buffer, self.window_width)
        if self.stats_manager is not None:
            self.stats_manager.set_metrics(
                target_timecode, {self._adaptive_ratio_key: adaptive_ratio}
            )
        return self._apply_cut_threshold(target_timecode, target_score, adaptive_ratio)

    def post_process(self, timecode: FrameTimecode) -> list[FrameTimecode]:
        """Evaluate any frames still buffered when the video ends.

        The last `window_width` frames never accumulate a full lookahead window, so they
        are scored here with the frames that are available (the window falls back to
        available frames at the end of the video). This ensures cuts near the end of the
        video are still detected and their `adaptive_ratio` metric is recorded.
        """
        cuts: list[FrameTimecode] = []
        required_frames = 1 + (2 * self.window_width)
        # With a full buffer, the last `window_width` frames are still unevaluated. If the
        # buffer never filled (video shorter than the required window), nothing was
        # evaluated yet, so all buffered frames are pending.
        first_pending = (
            len(self._buffer) - self.window_width if len(self._buffer) >= required_frames else 0
        )
        for index in range(first_pending, len(self._buffer)):
            (target_timecode, target_score) = self._buffer[index]
            adaptive_ratio = self._compute_adaptive_ratio(self._buffer, index)
            if self.stats_manager is not None:
                self.stats_manager.set_metrics(
                    target_timecode, {self._adaptive_ratio_key: adaptive_ratio}
                )
            cuts += self._apply_cut_threshold(target_timecode, target_score, adaptive_ratio)
        return cuts

    def _compute_adaptive_ratio(
        self, buffer: list[tuple[FrameTimecode, float]], target_index: int
    ) -> float:
        """Compute the adaptive ratio for the buffered frame at `target_index`, averaging
        the scores of the frames within `window_width` of it that are available in
        `buffer` (the window is truncated at the ends of the buffer)."""
        (_, target_score) = buffer[target_index]
        window_scores = [
            score
            for index, (_, score) in enumerate(buffer)
            if index != target_index and abs(index - target_index) <= self.window_width
        ]
        average_window_score = (
            sum(window_scores) / float(len(window_scores)) if window_scores else 0.0
        )

        average_is_zero = abs(average_window_score) < 0.00001

        if not average_is_zero:
            return min(target_score / average_window_score, 255.0)
        if target_score >= self.min_content_val:
            # if we would have divided by zero, set adaptive_ratio to the max (255.0)
            return 255.0
        return 0.0

    def _apply_cut_threshold(
        self, target_timecode: FrameTimecode, target_score: float, adaptive_ratio: float
    ) -> list[FrameTimecode]:
        """Emit a cut at `target_timecode` if the adaptive ratio and content value both
        exceed their thresholds, and `min_scene_len` has passed since the last cut."""
        # Check to see if adaptive_ratio exceeds the adaptive_threshold as well as there
        # being a large enough content_val to trigger a cut
        threshold_met: bool = (
            adaptive_ratio >= self.adaptive_threshold and target_score >= self.min_content_val
        )
        # Cuts are emitted at `target_timecode` (`window_width` behind `timecode`).
        # `_last_cut` is always set before any frame is buffered in process_frame.
        assert self._last_cut is not None
        min_length_met: bool = (target_timecode - self._last_cut) >= self.min_scene_len
        if threshold_met and min_length_met:
            self._last_cut = target_timecode
            return [target_timecode]
        return []
