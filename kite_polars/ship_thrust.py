# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Optimise a fixed-tether kite flight path for ship thrust with AWETrim.

Maximises the mean horizontal tether pull along the ship's course, which lies at
`thrust_azimuth` off the apparent downwind direction, minus `side_weight` times the
pull across it, under a tether force cap. Runs on the AWETrim branch ship-kite-thrust;
call with AWETrim's venv python from the AWETrim checkout.
"""
import argparse
import json
from pathlib import Path

import numpy as np
import yaml

from awetrim.environment.wind_factory import create_wind_model
from awetrim.identification.controls import flight_depower_match
from awetrim.kinematics.parametrized_patterns import (
    make_bspline_path_parameters_from_named_curve,
)
from awetrim.system.factory import create_system_model_from_yaml
from awetrim.timeseries.phase import Phase
from awetrim.utils.config_paths import LEI_V3_DOWNLOOP_SPLINE_CONFIG, LEI_V3_SYSTEM_CONFIG
from awetrim.utils.utils import load_cycle_config_from_yaml


def reelout_config(tether_length, max_force, thrust_azimuth, side_weight, guess,
                   depower, angle_band):
    """Fixed-tether reel-out config for the thrust target, with the kite pitched at
    `depower` and the angle of attack held in `angle_band` [rad] where given."""
    config, _ = load_cycle_config_from_yaml(LEI_V3_DOWNLOOP_SPLINE_CONFIG)
    config["path_parameters"] = make_bspline_path_parameters_from_named_curve(
        spline_type="periodic", r0=tether_length, **guess
    )
    config["radial_parameters"]["reeling_strategy"] = "constant"
    config["radial_parameters"]["reeling_speed"] = 0.0
    config["radial_parameters"]["max_tether_force"] = max_force
    sim = config["sim_parameters"]
    sim["start_angle"], sim["end_angle"] = guess["s_init"], guess["s_final"]
    sim["n_points"] = 100
    sim["input_depower"] = depower
    sim["reg_weight"] = 1.0
    sim["detect_simple_bounds"] = True
    sim["periodic_wrap"] = True
    sim["winch_mode"] = "free_speed"
    sim["opti_limits_override"] = {"speed_radial": [0.0, 0.0]}
    if angle_band is not None:
        sim["opti_limits_override"]["angle_of_attack"] = list(angle_band)
        sim["opti_limits_override"]["input_depower"] = [-0.3, 0.3]
    sim["thrust_azimuth"] = thrust_azimuth
    sim["side_weight"] = side_weight
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wind", type=float, default=10.0, help="apparent wind [m/s]")
    parser.add_argument("--azimuth", type=float, default=60.0,
                        help="course off apparent downwind [deg]")
    parser.add_argument("--side-weight", type=float, default=0.0)
    parser.add_argument("--max-force", type=float, default=None,
                        help="tether force cap [N], default the kite's rating")
    parser.add_argument("--tether", type=float, default=300.0, help="[m]")
    parser.add_argument("--kite", type=Path, default=None,
                        help="kite folder from awetrim_kite.py, default AWETrim's LEI-V3")
    parser.add_argument("--min-angle", type=float, default=5.0,
                        help="lowest angle of attack before the canopy flaps [deg]")
    args = parser.parse_args()

    guess = {"curve_type": "lissajous", "M": 10, "n_fit": 400, "s_init": 0.0,
             "s_final": 2.0 * np.pi, "az_amp0": 0.65, "beta0": 0.4, "beta_amp0": 0.30,
             "downloops": True}
    if args.kite is None:
        system_path, rom_path = LEI_V3_SYSTEM_CONFIG, None
        depower = flight_depower_match(LEI_V3_SYSTEM_CONFIG.parent, 2019)[0]
        angle_band, rating, parameters = None, 8400.0, ["C_phi", "C_beta"]
    else:
        system_path, rom_path = args.kite / "system.yaml", args.kite / "rom_vsm_rigid.yaml"
        rom = yaml.safe_load(rom_path.read_text())
        stall = rom["aerodynamics"]["params"]["angle_of_attack_stall"]
        depower, angle_band = 0.0, (np.radians(args.min_angle), stall)
        system_file = yaml.safe_load(system_path.read_text())
        rating = system_file["components"]["tethers"][0]["structure"]["max_tether_force"]
        parameters = ["C_phi", "C_beta", "input_depower"]
    max_force = rating if args.max_force is None else args.max_force
    config = reelout_config(args.tether, max_force, np.radians(args.azimuth),
                            args.side_weight, guess, depower, angle_band)
    system = create_system_model_from_yaml(yaml_path=system_path, aero_yaml_path=rom_path)
    system.wind = create_wind_model("uniform", U_ref=args.wind, z_ref=100.0)
    start = {"t": 0, "s": 0, "s_dot": 1, "input_steering": 0,
             "tension_tether_ground": 0.5 * max_force, "speed_radial": 0.0,
             "distance_radial": args.tether}
    phase = Phase(system_model=system, pattern_config=config, start_state=start)
    phase.run_simulation(phase_sim=True)
    phase.run_simulation_opti(optimization_params=parameters, target="thrust")
    flown, _ = phase.run_simulation(phase_sim=True)
    tension = flown.return_variable("tension_tether_ground")
    azimuth = flown.return_variable("angle_azimuth")
    elevation = flown.return_variable("angle_elevation")
    time = flown.return_variable("t")
    weights = np.gradient(time)
    pull = tension * np.cos(elevation) * weights
    offset = azimuth - np.radians(args.azimuth)
    result = {
        "mean_thrust": float(np.sum(pull * np.cos(offset)) / np.sum(weights)),
        "mean_side": float(np.sum(pull * np.sin(offset)) / np.sum(weights)),
        "tension_max": float(np.max(tension)),
        "azimuth_range_deg": [float(np.degrees(azimuth.min())),
                              float(np.degrees(azimuth.max()))],
        "elevation_range_deg": [float(np.degrees(elevation.min())),
                                float(np.degrees(elevation.max()))],
    }
    print(json.dumps(result))


if __name__ == "__main__":
    main()
