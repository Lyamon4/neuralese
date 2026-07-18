import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { open } from '@tauri-apps/plugin-dialog';
import { getCurrentWindow } from '@tauri-apps/api/window';
import './styles.css';

type InstallProgress = {
  phase: string;
  percent: number;
  current_file: string;
};

const appWindow = getCurrentWindow();
const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

const installPath = $('install-path') as HTMLInputElement;
const browseBtn = $('browse-btn') as HTMLButtonElement;
const installBtn = $('install-btn') as HTMLButtonElement;
const launchBtn = $('launch-btn') as HTMLButtonElement;
const finishBtn = $('finish-btn') as HTMLButtonElement;
const retryBtn = $('retry-btn') as HTMLButtonElement;
const closeBtn = $('close-btn') as HTMLButtonElement;
const minimizeBtn = $('minimize-btn') as HTMLButtonElement;

const progressFill = $('progress-fill');
const progressLabel = $('progress-label');
const progressStep = $('progress-step');
const progressFile = $('progress-file');
const errorMessage = $('error-message');

function showScreen(name: 'ready' | 'installing' | 'done' | 'error') {
  for (const el of Array.from(document.querySelectorAll('.screen'))) {
    el.classList.remove('active');
  }
  $(`screen-${name}`).classList.add('active');
}

function setProgress(progress: InstallProgress) {
  const value = Math.max(0, Math.min(100, progress.percent));
  progressFill.style.width = `${value}%`;
  progressStep.textContent = `${Math.round(value)}%`;
  progressLabel.textContent = progress.phase;
  progressFile.textContent = progress.current_file || '';
}

function bindWindowDrag() {
  for (const region of Array.from(document.querySelectorAll('[data-drag-region]'))) {
    region.addEventListener('mousedown', async (event) => {
      const mouseEvent = event as MouseEvent;
      const target = mouseEvent.target as HTMLElement;

      if (mouseEvent.button !== 0) {
        return;
      }

      if (target.closest('button, input')) {
        return;
      }

      await appWindow.startDragging();
    });
  }
}

async function boot() {
  bindWindowDrag();
  installPath.value = await invoke<string>('default_install_dir');

  await listen<InstallProgress>('install-progress', (event) => {
    setProgress(event.payload);
  });
}

browseBtn.addEventListener('click', async () => {
  const selected = await open({
    directory: true,
    multiple: false,
    title: 'Select install folder',
    defaultPath: installPath.value
  });

  if (typeof selected === 'string' && selected.length > 0) {
    installPath.value = selected;
  }
});

installBtn.addEventListener('click', async () => {
  installBtn.disabled = true;
  browseBtn.disabled = true;
  showScreen('installing');
  setProgress({ phase: 'Preparing', percent: 1, current_file: '' });

  try {
    await invoke('install', {
      options: {
        install_dir: installPath.value,
        create_desktop_shortcut: true,
        launch_after_install: false
      }
    });

    setProgress({ phase: 'Complete', percent: 100, current_file: '' });
    showScreen('done');
  } catch (err) {
    errorMessage.textContent = String(err);
    installBtn.disabled = false;
    browseBtn.disabled = false;
    showScreen('error');
  }
});

launchBtn.addEventListener('click', async () => {
  await invoke('launch_game', { installDir: installPath.value });
  await invoke('close_window');
});

finishBtn.addEventListener('click', () => invoke('close_window'));
retryBtn.addEventListener('click', () => showScreen('ready'));
closeBtn.addEventListener('click', () => invoke('close_window'));
minimizeBtn.addEventListener('click', () => invoke('minimize_window'));

boot().catch((err) => {
  errorMessage.textContent = String(err);
  showScreen('error');
});
