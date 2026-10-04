#!/usr/bin/env python3

"""Extract the AI-generated interactive Nanobeast poses as transparent layers."""

from pathlib import Path

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "AppStoreScreenshots" / "Outcome-Creature-Suite" / "Generated"
OUTPUT = ROOT / "AppStoreScreenshots" / "Outcome-Creature-Suite" / "Character-Layers"


# Coordinates are in each generated source image. The probable polygon stays tight
# around the creature; sure-foreground ellipses keep the main body intact.
CONFIG = {
    "bloomwraith": {
        "source": "02-bloomwraith-progress-scene.png",
        "polygon": [(375, 930), (550, 910), (730, 970), (852, 1040), (852, 1615),
                    (735, 1660), (585, 1640), (505, 1510), (470, 1290), (380, 1170)],
        "seeds": [((650, 1320), (20, 35)), ((610, 1460), (14, 24)), ((465, 1110), (10, 8))],
    },
    "overnode": {
        "source": "02-overnode-evolution-scene.png",
        "polygon": [(460, 1035), (610, 1010), (850, 1060), (852, 1585),
                    (730, 1640), (530, 1625), (470, 1480)],
        "seeds": [((650, 1290), (20, 40)), ((670, 1510), (14, 22)), ((510, 1210), (9, 15))],
    },
    "flarva": {
        "source": "01-flarva-rewarding-scene.png",
        "polygon": [(25, 1090), (175, 1050), (315, 1140), (335, 1450),
                    (270, 1585), (105, 1600), (30, 1510)],
        "seeds": [((180, 1270), (25, 25)), ((180, 1450), (18, 25))],
    },
    "ampaw": {
        "source": "03-ampaw-insights-scene.png",
        "polygon": [(20, 1110), (200, 1070), (390, 1200), (390, 1560),
                    (285, 1710), (85, 1680), (15, 1490)],
        "seeds": [((195, 1350), (25, 35)), ((200, 1510), (16, 20)), ((345, 1235), (8, 8))],
    },
    "tutoria": {
        "source": "05-tutoria-consistency-scene.png",
        "polygon": [(0, 1240), (110, 1180), (300, 1240), (345, 1460),
                    (280, 1690), (70, 1705), (0, 1610)],
        "seeds": [((165, 1440), (25, 35)), ((170, 1590), (16, 18)), ((275, 1280), (8, 12))],
    },
    "emberspout": {
        "source": "04-emberspout-discovery-scene.png",
        "polygon": [(485, 1090), (710, 1060), (898, 1160), (898, 1540),
                    (785, 1625), (570, 1580), (485, 1430)],
        "seeds": [((690, 1280), (28, 28)), ((745, 1480), (16, 18))],
    },
}

INTERACTIONS = {
    "bloomwraith-arm": ("02-bloomwraith-progress-scene.png", [(378, 1038), (410, 1032), (458, 1060), (565, 1110), (560, 1172), (510, 1160), (423, 1108), (378, 1085)], [((500, 1124), (8, 7))]),
    "overnode-hand": ("02-overnode-evolution-scene.png", [(478, 1100), (520, 1110), (548, 1160), (548, 1248), (520, 1305), (490, 1270), (474, 1210)], [((514, 1205), (7, 14)), ((500, 1260), (6, 10))]),
    "flarva-paw": ("01-flarva-rewarding-scene.png", [(232, 1288), (260, 1272), (302, 1294), (324, 1335), (302, 1388), (258, 1382), (232, 1348)], [((275, 1335), (11, 11))]),
    "ampaw-arm": ("03-ampaw-insights-scene.png", [(245, 1262), (282, 1204), (362, 1175), (386, 1203), (376, 1248), (316, 1282), (288, 1336), (252, 1322)], [((300, 1250), (10, 12)), ((365, 1212), (8, 7))]),
    "tutoria-paw": ("05-tutoria-consistency-scene.png", [(228, 1238), (248, 1195), (294, 1178), (322, 1218), (316, 1298), (300, 1352), (270, 1362), (242, 1318)], [((284, 1282), (10, 14)), ((270, 1218), (9, 9))]),
    "emberspout-paw": ("04-emberspout-discovery-scene.png", [(518, 1382), (555, 1360), (598, 1385), (620, 1440), (603, 1518), (570, 1552), (535, 1510)], [((570, 1450), (14, 22))]),
}


def polygon_mask(shape: tuple[int, int], points: list[tuple[int, int]]) -> np.ndarray:
    result = np.zeros(shape, dtype=np.uint8)
    cv2.fillPoly(result, [np.array(points, dtype=np.int32)], 255)
    return result


def extract(name: str, config: dict) -> Path:
    image = cv2.imread(str(SOURCE / config["source"]), cv2.IMREAD_COLOR)
    if image is None:
        raise FileNotFoundError(SOURCE / config["source"])

    height, width = image.shape[:2]
    probable = polygon_mask((height, width), config["polygon"])
    mask = np.full((height, width), cv2.GC_BGD, dtype=np.uint8)
    mask[probable == 255] = cv2.GC_PR_FGD
    for center, axes in config["seeds"]:
        cv2.ellipse(mask, center, axes, 0, 0, 360, cv2.GC_FGD, -1)

    bg_model = np.zeros((1, 65), np.float64)
    fg_model = np.zeros((1, 65), np.float64)
    cv2.grabCut(image, mask, None, bg_model, fg_model, 10, cv2.GC_INIT_WITH_MASK)
    alpha = np.where(
        (mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0
    ).astype(np.uint8)
    alpha = cv2.morphologyEx(alpha, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.7)

    rgba = cv2.cvtColor(image, cv2.COLOR_BGR2BGRA)
    rgba[:, :, 3] = alpha
    OUTPUT.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT / f"{name}.png"
    cv2.imwrite(str(destination), rgba)
    cv2.imwrite(str(OUTPUT / f"{name}-mask.png"), alpha)
    return destination


def extract_interaction(name: str, source_name: str, points: list[tuple[int, int]], seeds: list[tuple[tuple[int, int], tuple[int, int]]]) -> Path:
    image = cv2.imread(str(SOURCE / source_name), cv2.IMREAD_COLOR)
    if image is None:
        raise FileNotFoundError(SOURCE / source_name)
    height, width = image.shape[:2]
    probable = polygon_mask((height, width), points)
    mask = np.full((height, width), cv2.GC_BGD, dtype=np.uint8)
    mask[probable == 255] = cv2.GC_PR_FGD
    for center, axes in seeds:
        cv2.ellipse(mask, center, axes, 0, 0, 360, cv2.GC_FGD, -1)
    bg_model = np.zeros((1, 65), np.float64)
    fg_model = np.zeros((1, 65), np.float64)
    cv2.grabCut(image, mask, None, bg_model, fg_model, 8, cv2.GC_INIT_WITH_MASK)
    alpha = np.where(
        (mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0
    ).astype(np.uint8)
    alpha = cv2.morphologyEx(alpha, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.9)
    rgba = cv2.cvtColor(image, cv2.COLOR_BGR2BGRA)
    rgba[:, :, 3] = alpha
    OUTPUT.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT / f"{name}.png"
    cv2.imwrite(str(destination), rgba)
    return destination


if __name__ == "__main__":
    for interaction_name, (source_name, points, seeds) in INTERACTIONS.items():
        print(extract_interaction(interaction_name, source_name, points, seeds))
