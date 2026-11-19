# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later
# The TeX Live the paper, the extended abstract and the kite design paper build in:
# the medium scheme plus the packages they load that it lacks.
FROM texlive/texlive:latest-medium
# A stale mirror makes tlmgr skip a package yet exit 0, so the build checks the local
# database for each one and retries: every tlmgr run picks its mirror afresh.
RUN packages="elsarticle cleveref fontaxes newtx placeins titlesec xurl"; \
    for attempt in 1 2 3; do \
        tlmgr install $packages; \
        tlmgr info --only-installed --data installed $packages >/dev/null && exit 0; \
        echo "tlmgr attempt $attempt left a package uninstalled, named above" >&2; \
    done; \
    exit 1
