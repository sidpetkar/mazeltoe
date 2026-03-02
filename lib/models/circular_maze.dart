import 'dart:math';

class CircularCell {
  final int ring;
  final int sector;

  bool visited = false;
  bool innerWall = true;
  late List<bool> outerWalls;
  bool ccwWall = true;
  bool cwWall = true;

  CircularCell({
    required this.ring,
    required this.sector,
    int outerNeighborCount = 1,
  }) {
    outerWalls = List.filled(outerNeighborCount, true);
  }

  bool get hasAnyOuterWall => outerWalls.any((w) => w);
  bool get allOuterWallsOpen => outerWalls.every((w) => !w);
}

class CircularMaze {
  final int rings;
  final List<int> sectorsPerRing;
  late final List<List<CircularCell>> grid;

  CircularMaze({required this.rings, required this.sectorsPerRing}) {
    grid = List.generate(rings, (ring) {
      final sectors = sectorsPerRing[ring];
      final outerCount = ring < rings - 1
          ? sectorsPerRing[ring + 1] ~/ sectorsPerRing[ring]
          : 1;
      return List.generate(
        sectors,
        (sector) => CircularCell(
          ring: ring,
          sector: sector,
          outerNeighborCount: outerCount,
        ),
      );
    });
  }

  int get sectors => sectorsPerRing.last;

  void generateDfs() {
    final random = Random();

    for (final ring in grid) {
      for (final cell in ring) {
        cell.visited = false;
        cell.innerWall = true;
        cell.outerWalls.fillRange(0, cell.outerWalls.length, true);
        cell.ccwWall = true;
        cell.cwWall = true;
      }
    }

    final stack = <CircularCell>[];
    var current = grid[0][0];
    current.visited = true;

    while (true) {
      final neighbors = _unvisitedNeighbors(current);
      if (neighbors.isNotEmpty) {
        final next = neighbors[random.nextInt(neighbors.length)];
        _removeWallBetween(current, next);
        stack.add(current);
        current = next;
        current.visited = true;
      } else if (stack.isNotEmpty) {
        current = stack.removeLast();
      } else {
        break;
      }
    }
  }

  List<CircularCell> _unvisitedNeighbors(CircularCell cell) {
    final out = <CircularCell>[];
    final ring = cell.ring;
    final sector = cell.sector;
    final sectorCount = sectorsPerRing[ring];

    // ccw / cw within same ring
    final ccw = grid[ring][(sector - 1 + sectorCount) % sectorCount];
    if (!ccw.visited) out.add(ccw);

    final cw = grid[ring][(sector + 1) % sectorCount];
    if (!cw.visited) out.add(cw);

    // Inward
    if (ring > 0) {
      final innerSectors = sectorsPerRing[ring - 1];
      final ratio = sectorCount ~/ innerSectors;
      if (ratio == 1) {
        final inward = grid[ring - 1][sector];
        if (!inward.visited) out.add(inward);
      } else {
        final parentSector = sector ~/ ratio;
        final inward = grid[ring - 1][parentSector];
        if (!inward.visited) out.add(inward);
      }
    }

    // Outward
    if (ring < rings - 1) {
      final outerSectors = sectorsPerRing[ring + 1];
      final ratio = outerSectors ~/ sectorCount;
      if (ratio == 1) {
        final outward = grid[ring + 1][sector];
        if (!outward.visited) out.add(outward);
      } else {
        for (int i = 0; i < ratio; i++) {
          final childSector = sector * ratio + i;
          final outward = grid[ring + 1][childSector];
          if (!outward.visited) out.add(outward);
        }
      }
    }

    return out;
  }

  void _removeWallBetween(CircularCell a, CircularCell b) {
    if (a.ring == b.ring) {
      final sectorCount = sectorsPerRing[a.ring];
      final delta = (b.sector - a.sector + sectorCount) % sectorCount;
      if (delta == 1) {
        a.cwWall = false;
        b.ccwWall = false;
      } else {
        a.ccwWall = false;
        b.cwWall = false;
      }
      return;
    }

    // Determine which is inner, which is outer
    final CircularCell inner;
    final CircularCell outer;
    if (a.ring < b.ring) {
      inner = a;
      outer = b;
    } else {
      inner = b;
      outer = a;
    }

    final innerSectors = sectorsPerRing[inner.ring];
    final outerSectors = sectorsPerRing[outer.ring];
    final ratio = outerSectors ~/ innerSectors;

    if (ratio == 1) {
      inner.outerWalls[0] = false;
      outer.innerWall = false;
    } else {
      final childIndex = outer.sector - inner.sector * ratio;
      inner.outerWalls[childIndex] = false;
      outer.innerWall = false;
    }
  }
}
