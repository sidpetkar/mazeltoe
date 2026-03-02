class Cell {
  final int row;
  final int col;
  bool visited = false;
  bool topWall = true;
  bool rightWall = true;
  bool bottomWall = true;
  bool leftWall = true;

  Cell({required this.row, required this.col});

  void removeWall(Cell neighbor) {
    final dRow = neighbor.row - row;
    final dCol = neighbor.col - col;

    if (dRow == -1 && dCol == 0) {
      topWall = false;
      neighbor.bottomWall = false;
    } else if (dRow == 1 && dCol == 0) {
      bottomWall = false;
      neighbor.topWall = false;
    } else if (dRow == 0 && dCol == 1) {
      rightWall = false;
      neighbor.leftWall = false;
    } else if (dRow == 0 && dCol == -1) {
      leftWall = false;
      neighbor.rightWall = false;
    }
  }

  bool hasUnvisitedNeighbors(List<List<Cell>> grid) {
    final neighbors = getUnvisitedNeighbors(grid);
    return neighbors.isNotEmpty;
  }

  List<Cell> getUnvisitedNeighbors(List<List<Cell>> grid) {
    final List<Cell> neighbors = [];
    final int rows = grid.length;
    final int cols = grid[0].length;

    // Top
    if (row > 0 && !grid[row - 1][col].visited) {
      neighbors.add(grid[row - 1][col]);
    }
    // Right
    if (col < cols - 1 && !grid[row][col + 1].visited) {
      neighbors.add(grid[row][col + 1]);
    }
    // Bottom
    if (row < rows - 1 && !grid[row + 1][col].visited) {
      neighbors.add(grid[row + 1][col]);
    }
    // Left
    if (col > 0 && !grid[row][col - 1].visited) {
      neighbors.add(grid[row][col - 1]);
    }

    return neighbors;
  }
}
