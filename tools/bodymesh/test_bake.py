#!/usr/bin/env python3
"""Unit tests for bake.py. Stdlib only: run with `python3 tools/bodymesh/test_bake.py`."""
import struct
import sys
import unittest

sys.path.insert(0, __file__.rsplit("/", 1)[0])

import bake


class TestParsing(unittest.TestCase):
    def test_parse_obj_reads_positions_and_grouped_faces(self):
        lines = [
            "v 0 0 0\n", "v 1 0 0\n", "v 1 1 0\n", "v 0 1 0\n",
            "g body\n", "f 1/1 2/2 3/3 4/4\n",
            "g helper-skirt\n", "f 4 3 2 1\n",
        ]
        positions, faces = bake.parse_obj(lines)
        self.assertEqual(positions, [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)])
        self.assertEqual(faces, [("body", [0, 1, 2, 3]), ("helper-skirt", [3, 2, 1, 0])])

    def test_parse_target_skips_comments_and_reads_deltas(self):
        lines = ["# comment\n", "\n", "0 .5 -1 2\n", "7 1 1 1\n"]
        self.assertEqual(bake.parse_target(lines), {0: (0.5, -1.0, 2.0), 7: (1.0, 1.0, 1.0)})

    def test_apply_target_offsets_named_indices_and_ignores_out_of_range(self):
        positions = [(0, 0, 0), (1, 1, 1)]
        out = bake.apply_target(positions, {1: (1, 2, 3), 99: (9, 9, 9)})
        self.assertEqual(out, [(0, 0, 0), (2, 3, 4)])


class TestGeometry(unittest.TestCase):
    def test_compact_drops_unreferenced_vertices_and_remaps(self):
        positions = [(0, 0, 0), (9, 9, 9), (1, 0, 0), (1, 1, 0)]
        positions, faces = bake.compact(positions, [[0, 2, 3]])
        self.assertEqual(positions, [(0, 0, 0), (1, 0, 0), (1, 1, 0)])
        self.assertEqual(faces, [[0, 1, 2]])

    def test_triangulate_fans_a_quad_preserving_winding(self):
        self.assertEqual(bake.triangulate([[0, 1, 2, 3]]), [(0, 1, 2), (0, 2, 3)])

    def test_build_adjacency_links_face_neighbours_both_ways(self):
        adjacency = bake.build_adjacency([[0, 1, 2]], 3)
        self.assertEqual(adjacency[0], {1, 2})
        self.assertEqual(adjacency[1], {0, 2})

    def test_taubin_smooth_applies_the_shrink_then_unshrink_pair(self):
        # Neighbour mean is (1, 0, 0). The lambda pass pulls 9 -> 4.5, the
        # negative mu pass pushes it back out to 4.5 + 0.53 * 4.5 = 6.885.
        positions = [(0, 0, 0), (2, 0, 0), (1, 9, 0)]
        adjacency = [{2}, {2}, {0, 1}]
        out = bake.taubin_smooth(positions, adjacency, region={2}, iterations=1)
        self.assertAlmostEqual(out[2][0], 1.0, places=6)
        self.assertAlmostEqual(out[2][1], 6.885, places=6)

    def test_taubin_smooth_anchors_vertices_outside_the_region(self):
        positions = [(0, 0, 0), (2, 0, 0), (1, 9, 0)]
        adjacency = [{2}, {2}, {0, 1}]
        out = bake.taubin_smooth(positions, adjacency, region=set(), iterations=3)
        self.assertEqual(out, positions)

    def test_taubin_retains_far_more_amplitude_than_a_pure_laplacian(self):
        """Dlaczego: to jest caly powod wyboru Taubina. Przy tej samej liczbie
        usrednien czysty laplasjan zwija bryle (0.5^8), a Taubin nie (0.765^4).

        Uwaga na interpretacje: Taubin chroni NISKIE czestotliwosci, a w
        trojwierzcholkowej zabawce caly sygnal jest wysokoczestotliwosciowy,
        wiec tutaj tez opada — tylko duzo wolniej. Zachowanie bryly widac
        dopiero na prawdziwej siatce i pilnuje go krok weryfikacji w zadaniu 2."""
        positions = [(-1, 0, 0), (1, 0, 0), (0, 1, 0)]
        adjacency = [{2}, {2}, {0, 1}]
        taubin = bake.taubin_smooth(positions, adjacency, region={2}, iterations=4)
        laplacian = positions
        for _ in range(8):
            laplacian = bake.smoothing_pass(laplacian, adjacency, {2}, 0.5)
        self.assertAlmostEqual(taubin[2][1], 0.765 ** 4, places=6)
        self.assertAlmostEqual(laplacian[2][1], 0.5 ** 8, places=6)
        self.assertGreater(taubin[2][1], laplacian[2][1])

    def test_normalise_puts_feet_at_zero_height_at_one_and_centres_xz(self):
        out = bake.normalise([(-2, 10, 4), (2, 30, 8)])
        self.assertEqual(out, [(-0.1, 0.0, -0.1), (0.1, 1.0, 0.1)])

    def test_normalisation_of_reports_the_transform_normalise_applies(self):
        cx, y0, cz, height = bake.normalisation_of([(-2, 10, 4), (2, 30, 8)])
        self.assertEqual((cx, y0, cz, height), (0.0, 10.0, 6.0, 20.0))

    def test_normalise_with_matches_normalise_on_the_same_points(self):
        """Dlaczego: szkielet i siatka musza przejsc DOKLADNIE te sama
        transformacje, inaczej stawy nie trafiaja w cialo."""
        positions = [(-2, 10, 4), (2, 30, 8)]
        transform = bake.normalisation_of(positions)
        self.assertEqual(bake.normalise_with(positions, transform), bake.normalise(positions))

    def test_normalise_with_maps_a_point_outside_the_source_set(self):
        transform = bake.normalisation_of([(-2, 10, 4), (2, 30, 8)])
        self.assertEqual(bake.normalise_with([(0, 20, 6)], transform), [(0.0, 0.5, 0.0)])

    def test_compute_normals_faces_along_positive_z_for_ccw_winding(self):
        normals = bake.compute_normals([(0, 0, 0), (1, 0, 0), (0, 1, 0)], [(0, 1, 2)])
        for normal in normals:
            self.assertAlmostEqual(normal[2], 1.0, places=6)


class TestEncoding(unittest.TestCase):
    def test_encode_bodymesh_round_trips_through_struct(self):
        blob = bake.encode_bodymesh([(1, 2, 3)], [(0, 1, 0)], [(0, 0, 0)])
        self.assertEqual(blob[:4], b"BMSH")
        version, vertex_count, index_count = struct.unpack_from("<III", blob, 4)
        self.assertEqual((version, vertex_count, index_count), (1, 1, 3))
        self.assertEqual(struct.unpack_from("<fff", blob, 16), (1.0, 2.0, 3.0))
        self.assertEqual(len(blob), 16 + 12 + 12 + 12)


if __name__ == "__main__":
    unittest.main()
