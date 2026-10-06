"""Render the real SwiftUI guide with isolated data; compile preview-onboarding.sh first."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
exe = root / 'build.noindex/OnboardingPreview.app/Contents/MacOS/OnboardingPreview'
out = root / 'Evidence/onboarding'
out.mkdir(parents=True, exist_ok=True)
with (out / 'renders.log').open('w') as log:
    for language in ['english', 'chinese']:
        for step in range(4):
            for size in ['minimum', 'default']:
                args = [str(exe), '--language', language, '--step', str(step), '--render',
                        '--output', str(out / f'{language}-step{step + 1}-{size}.png')]
                if size == 'minimum':
                    args += ['--minimum']
                subprocess.run(args, check=True, stdout=log, stderr=log, timeout=20)
    fixtures = [
        ('failure-en', ['--step', '1', '--failure']),
        ('failure-zh', ['--step', '1', '--failure', '--language', 'chinese']),
        ('saved-en', ['--step', '1', '--saved']),
        ('stale-zh', ['--step', '1', '--saved', '--stale', '--language', 'chinese']),
        ('dark-display', ['--step', '2', '--dark']),
        ('dark-welcome-zh', ['--language', 'chinese', '--dark']),
        ('reduced-motion', ['--step', '2', '--reduce-motion']),
        ('ready-saved', ['--step', '3', '--saved'])]
    for name, extra in fixtures:
        subprocess.run([str(exe), '--minimum', '--render', '--output', str(out / f'{name}.png')] + extra,
                       check=True, stdout=log, stderr=log, timeout=20)
print('24 native renders finished. Fixture values are synthetic.')
