# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later
# The TeX Live the paper, the extended abstract and the kite design paper build in:
# the medium scheme plus the packages they load that it lacks.
FROM texlive/texlive:latest-medium
# tlmgr can exit 0 having installed nothing, so the build checks each package landed.
RUN packages="elsarticle cleveref fontaxes newtx placeins titlesec xurl" \
    && tlmgr install $packages \
    && ! tlmgr info --data installed $packages | grep -qx 0
