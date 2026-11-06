"""Write an AWETrim kite folder for a rigid-shape ram-air kite from its VSM polar.

The system file starts from AWETrim's LEI-V3 one with area, span, masses, bridle,
control unit and tether replaced by the ship-kite values; the reduced-order model fits
CL and CD as polynomials in angle of attack to output/kite_ar<AR>.csv, adds the bridle
drag, and pitches the kite on the tether through the depower input [rad], so the
optimiser trims the angle of attack instead of flapping the canopy. Run with AWETrim's
venv python.
"""
import argparse
import copy
from pathlib import Path

import numpy as np
import yaml

from awetrim.utils.config_paths import LEI_V3_SYSTEM_CONFIG

HERE = Path(__file__).parent
FLATTENING = 0.82


def bridle_lines(area, aspect_ratio, max_force, settings):
    """Drag coefficient, total line length [m], diameter [m] and mass [kg] of the
    bridle, as `bridle_lines` in WindShipOpt's rig.jl."""
    span = np.sqrt(area * aspect_ratio)
    count = settings["bridle_rows"] * aspect_ratio / settings["bridle_spacing"]
    diameter = np.sqrt(4 * max_force / (count * np.pi * settings["tether_stress"]))
    length = (settings["bridle_cascade_factor"] * count
              * settings["bridle_height_ratio"] * span)
    drag = settings["line_drag_coefficient"] * length * diameter / area
    mass = settings["rope_density"] * np.pi * diameter**2 / 4 * length
    return drag, length, diameter, mass


def polar_fit(aspect_ratio, bridle_drag, stall_margin):
    """CL and CD polynomials in alpha [rad] up to stall minus `stall_margin` [rad]."""
    data = np.loadtxt(HERE / "output" / f"kite_ar{aspect_ratio:.0f}.csv", delimiter=",",
                      skiprows=1)
    alpha = np.radians(data[:, 0])
    stall = alpha[np.argmax(data[:, 1])]
    used = alpha <= stall
    lift = np.polynomial.polynomial.polyfit(alpha[used], data[used, 1], 3)
    drag = np.polynomial.polynomial.polyfit(alpha[used], data[used, 2], 2)
    terms = lambda c: [{"var": "alpha", "power": k, "coef": float(c[k])}
                       for k in range(1, len(c))]
    return {"CL0": float(lift[0]), "CD0": float(drag[0] + bridle_drag),
            "CL": terms(lift), "CD": terms(drag), "stall": float(stall - stall_margin)}


def write_kite(area, aspect_ratio, settings, output):
    """System and ROM yaml for one kite; returns their paths."""
    max_force = settings["max_force_per_area"] * area
    bridle_drag, line_length, line_diameter, bridle_mass = bridle_lines(
        area, aspect_ratio, max_force, settings)
    span = np.sqrt(area * aspect_ratio)
    tether_diameter = np.sqrt(4 * max_force / (np.pi * settings["tether_stress"]))
    fit = polar_fit(aspect_ratio, bridle_drag, np.radians(2.0))

    system = yaml.safe_load(LEI_V3_SYSTEM_CONFIG.read_text())
    kite = system["components"]["kites"][0]
    wing = kite["wing"]["structure"]
    wing_mass = settings["canopy_mass_per_area"] * area
    scale = span / wing["span"]
    mass_scale = (wing_mass + bridle_mass) / (wing["mass"] + kite["bridle"]["structure"]["mass"])
    wing["projected_surface_area"] = area
    wing["planform_surface_area"] = area / FLATTENING
    wing["span"] = float(span)
    wing["mass"] = float(wing_mass)
    wing["center_of_mass"] = [0.0, 0.0, float(settings["bridle_height_ratio"] * span)]
    wing["inertia_tensor"] = (np.array(wing["inertia_tensor"]) * mass_scale * scale**2).tolist()
    wing["side_projected_area"] = float(wing["side_projected_area"] * scale**2)
    bridle = kite["bridle"]["structure"]
    bridle["total_nominal_line_length"] = float(line_length)
    bridle["avg_line_diameter"] = float(line_diameter)
    bridle["mass"] = float(bridle_mass)
    control = kite["control_system"]["structure"]
    control["mass"] = settings["control_unit_mass_per_force"] * max_force
    control["length"], control["diameter"] = 2.0, 1.0
    control["depower"]["range"] = [-0.3, 0.3]
    tether = system["components"]["tethers"][0]["structure"]
    tether["length"] = settings["tether_length"] + 15.0
    tether["diameter"] = float(tether_diameter)
    tether["density"] = settings["rope_density"]
    tether["max_tether_force"] = float(max_force)
    system["components"]["ground_station"]["drums"][0]["max_tether_force"] = float(max_force)
    name = f"SHIP-RAMAIR-A{area:.0f}-AR{aspect_ratio:.0f}"
    system["metadata"]["name"] = name
    rom_name = "rom_vsm_rigid.yaml"
    system["models"]["reduced_order"]["aerodynamics"] = rom_name

    rom = yaml.safe_load((LEI_V3_SYSTEM_CONFIG.parent / "rom_config_aerostructural.yaml")
                         .read_text())
    rom["metadata"] = {"description": f"Rigid-shape VSM polar of a ram-air kite, AR "
                       f"{aspect_ratio:.0f}, bridle drag in CD, KCU drag from the system file"}
    rom["controls"]["input_depower"] = {"powered": 0.0, "depowered": 0.3}
    rom["validity"]["angle_of_attack_deg"] = [-4.0, float(np.degrees(fit["stall"]))]
    rom["validity"]["input_depower"] = [-0.3, 0.3]
    rom["validity"]["min_tether_force_n"] = float(0.005 * max_force)
    aero = rom["aerodynamics"]
    aero["reference_area"] = area
    params = aero["params"]
    params["CL0"], params["CD0"] = fit["CL0"], fit["CD0"]
    params["angle_pitch_tether_0"] = 0.0
    params["slope_angle_pitch_tether_depower"] = 1.0
    v3_depower = 1.595
    params["gain_roll_steering"] = float(np.polynomial.polynomial.polyval(
        v3_depower, [params["gain_roll_steering"], *params["gain_roll_steering_depower"]]))
    params["gain_roll_steering_depower"] = []
    params["angle_of_attack_stall"] = fit["stall"]
    aero["coefficients"] = {"CL": fit["CL"], "CD": fit["CD"]}

    folder = Path(output) / name
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "system.yaml").write_text(yaml.safe_dump(system, sort_keys=False))
    (folder / rom_name).write_text(yaml.safe_dump(rom, sort_keys=False))
    return folder / "system.yaml", folder / rom_name


SETTINGS = {
    "max_force_per_area": 500.0, "tether_stress": 4e8, "rope_density": 830.0,
    "tether_length": 400.0, "canopy_mass_per_area": 0.3,
    "control_unit_mass_per_force": 0.22e-3,
    "bridle_rows": 4.0, "bridle_spacing": 0.4, "bridle_height_ratio": 0.7,
    "bridle_cascade_factor": 0.6, "line_drag_coefficient": 1.1,
}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--area", type=float, default=800.0)
    parser.add_argument("--aspect-ratio", type=float, default=5.0)
    parser.add_argument("--output", default=str(HERE / "output" / "awetrim"))
    args = parser.parse_args()
    for path in write_kite(args.area, args.aspect_ratio, SETTINGS, args.output):
        print(path)
