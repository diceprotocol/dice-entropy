#!/bin/bash
cd apps/tyche || exit 1
cargo sqlx prepare --check
