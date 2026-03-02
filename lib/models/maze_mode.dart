enum MazeMode {
  box,
  circular,
  circularRotating,
  slidingBox,
}

extension MazeModeLabel on MazeMode {
  String get title {
    switch (this) {
      case MazeMode.box:
        return 'Box Grid';
      case MazeMode.circular:
        return 'Circular Grid';
      case MazeMode.circularRotating:
        return 'Rotating Maze';
      case MazeMode.slidingBox:
        return 'Sliding Grid';
    }
  }

  String get storageKey {
    switch (this) {
      case MazeMode.box:
        return 'box';
      case MazeMode.circular:
        return 'circular';
      case MazeMode.circularRotating:
        return 'circularRotating';
      case MazeMode.slidingBox:
        return 'slidingBox';
    }
  }

  int get startLevel {
    switch (this) {
      case MazeMode.box:
      case MazeMode.circular:
      case MazeMode.slidingBox:
        return 1;
      case MazeMode.circularRotating:
        return 21;
    }
  }
}
