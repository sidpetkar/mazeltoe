import 'dart:math';
import 'cell.dart';

class Maze {
  final int rows;
  final int cols;
  late List<List<Cell>> grid;

  Maze({required this.rows, required this.cols}) {
    _initializeGrid();
  }

  void _initializeGrid() {
    grid = List.generate(
      rows,
      (r) => List.generate(cols, (c) => Cell(row: r, col: c)),
    );
  }

  void generate() {
    _initializeGrid();
    final random = Random();
    final stack = <Cell>[];
    Cell current = grid[0][0];
    current.visited = true;

    do {
      final neighbors = current.getUnvisitedNeighbors(grid);
      if (neighbors.isNotEmpty) {
        final next = neighbors[random.nextInt(neighbors.length)];
        stack.add(current);
        current.removeWall(next);
        current = next;
        current.visited = true;
      } else if (stack.isNotEmpty) {
        current = stack.removeLast();
      }
    } while (stack.isNotEmpty);
  }

  Cell get startCell => grid[0][0];
  Cell get endCell => grid[rows - 1][cols - 1];

  bool canMove(int row, int col, int dRow, int dCol) {
    if (row < 0 || row >= rows || col < 0 || col >= cols) return false;

    final cell = grid[row][col];

    if (dRow == -1 && dCol == 0) return !cell.topWall;
    if (dRow == 1 && dCol == 0) return !cell.bottomWall;
    if (dRow == 0 && dCol == 1) return !cell.rightWall;
    if (dRow == 0 && dCol == -1) return !cell.leftWall;

    return false;
  }

  bool isAtGoal(double x, double y, double cellSize) {
    final goalRow = rows - 1;
    final goalCol = cols - 1;
    final goalX = goalCol * cellSize + cellSize / 2;
    final goalY = goalRow * cellSize + cellSize / 2;
    final threshold = cellSize * 0.4;

    final dx = x - goalX;
    final dy = y - goalY;
    return (dx * dx + dy * dy) <= threshold * threshold;
  }
}
