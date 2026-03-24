"""Unit tests for the skills install module."""

import pytest
from unittest.mock import patch, MagicMock
import pathlib
import os
import tempfile
import shutil
import subprocess

from eurekaclaw.skills.install import install_from_hub, install_seed_skills, CLAWHUB_REGISTRY, SEED_SKILL_REPO, SEED_SKILL_REPO_FOLDER, SEED_SKILL_FOLDER


class TestInstallFromHub:
    @patch('eurekaclaw.skills.install.subprocess.run')
    @patch('eurekaclaw.skills.install.os.makedirs')
    @patch('eurekaclaw.skills.install.os.path.exists')
    def test_install_from_hub_success(self, mock_exists, mock_makedirs, mock_run):
        """Test successful installation from hub."""
        mock_exists.return_value = False
        mock_run.return_value = MagicMock()

        with tempfile.TemporaryDirectory(delete=False) as temp_dir:
            dest = pathlib.Path(temp_dir) / "skills"
            result = install_from_hub("self-improving-agent", dest)

            mock_makedirs.assert_called_once_with(dest)
            mock_run.assert_called_once_with(
                ["clawhub", "install", "self-improving-agent"],
                check=True,
                text=True,
                cwd=dest.parent,
            )
            assert result is True

    @patch('eurekaclaw.skills.install.subprocess.run')
    @patch('eurekaclaw.skills.install.os.makedirs')
    @patch('eurekaclaw.skills.install.os.path.exists')
    def test_install_from_hub_clawhub_not_found(self, mock_exists, mock_makedirs, mock_run):
        """Test when clawhub CLI is not found."""
        mock_exists.return_value = False
        mock_run.side_effect = FileNotFoundError()

        with tempfile.TemporaryDirectory() as temp_dir:
            dest = pathlib.Path(temp_dir) / "skill_dir"
            result = install_from_hub("no exist skill", dest)

            assert result is False

    @patch('eurekaclaw.skills.install.subprocess.run')
    @patch('eurekaclaw.skills.install.os.makedirs')
    @patch('eurekaclaw.skills.install.os.path.exists')
    def test_install_from_hub_installation_failed(self, mock_exists, mock_makedirs, mock_run):
        """Test when installation fails."""
        mock_exists.return_value = False
        mock_run.side_effect = subprocess.CalledProcessError(1, "clawhub")

        with tempfile.TemporaryDirectory() as temp_dir:
            dest = pathlib.Path(temp_dir) / "skill_dir"
            result = install_from_hub("test-skill", dest)

            assert result is False

    @patch('eurekaclaw.skills.install.subprocess.run')
    @patch('eurekaclaw.skills.install.os.makedirs')
    @patch('eurekaclaw.skills.install.os.path.exists')
    def test_install_from_hub_dest_exists(self, mock_exists, mock_makedirs, mock_run):
        """Test when destination directory already exists."""
        mock_exists.return_value = True
        mock_run.return_value = MagicMock()

        with tempfile.TemporaryDirectory() as temp_dir:
            dest = pathlib.Path(temp_dir) / "skill_dir"
            result = install_from_hub("test-skill", dest)

            mock_makedirs.assert_not_called()
            mock_run.assert_called_once()
            assert result is True


# class TestInstallSeedSkills:
#     @patch('eurekaclaw.skills.install.shutil.rmtree')
#     @patch('eurekaclaw.skills.install.copy_directory')
#     @patch('eurekaclaw.skills.install.os.listdir')
#     @patch('eurekaclaw.skills.install.os.path.join')
#     @patch('eurekaclaw.skills.install.os.path.isdir')
#     @patch('eurekaclaw.skills.install.subprocess.run')
#     @patch('eurekaclaw.skills.install.os.makedirs')
#     @patch('eurekaclaw.skills.install.os.path.exists')
#     def test_install_seed_skills_success(self, mock_exists, mock_makedirs, mock_run, mock_isdir, mock_join, mock_listdir, mock_copy_directory, mock_rmtree):
#         """Test successful installation of seed skills."""
#         mock_exists.return_value = False
#         mock_run.return_value = MagicMock()
#         mock_listdir.return_value = ["skill1", ".git", "skill2"]
#         mock_isdir.side_effect = lambda path: not path.endswith(".git")
#         mock_join.side_effect = lambda *args: "/".join(args)

#         with tempfile.TemporaryDirectory() as temp_dir:
#             dest = pathlib.Path(temp_dir)
#             install_seed_skills(dest)

#             mock_makedirs.assert_called_once_with(dest)
#             mock_run.assert_called_once_with(
#                 ["git", "clone", SEED_SKILL_REPO],
#                 check=True,
#                 text=True,
#                 cwd=dest,
#             )
#             # Should copy skill1 and skill2, but not .git
#             assert mock_copy_directory.call_count == 2
#             mock_rmtree.assert_called_once()

#     @patch('eurekaclaw.skills.install.subprocess.run')
#     @patch('eurekaclaw.skills.install.os.makedirs')
#     @patch('eurekaclaw.skills.install.os.path.exists')
#     def test_install_seed_skills_git_clone_fails(self, mock_exists, mock_makedirs, mock_run):
#         """Test when git clone fails."""
#         mock_exists.return_value = False
#         mock_run.side_effect = Exception("Git clone failed")

#         with tempfile.TemporaryDirectory() as temp_dir:
#             dest = pathlib.Path(temp_dir)
#             with patch('builtins.print') as mock_print:
#                 install_seed_skills(dest)

#             mock_print.assert_called_once_with("Error installing seed skills: Git clone failed")

#     @patch('eurekaclaw.skills.install.subprocess.run')
#     @patch('eurekaclaw.skills.install.os.makedirs')
#     @patch('eurekaclaw.skills.install.os.path.exists')
#     def test_install_seed_skills_dest_exists(self, mock_exists, mock_makedirs, mock_run):
#         """Test when destination directory already exists."""
#         mock_exists.return_value = True
#         mock_run.return_value = MagicMock()

#         with tempfile.TemporaryDirectory() as temp_dir:
#             dest = pathlib.Path(temp_dir)
#             install_seed_skills(dest)

#             mock_makedirs.assert_not_called()
#             mock_run.assert_called_once()


# class TestMainBlock:
#     @patch('eurekaclaw.skills.install.install_seed_skills')
#     @patch('eurekaclaw.skills.install.install_from_hub')
#     @patch('pathlib.Path.home')
#     def test_main_block(self, mock_home, mock_install_from_hub, mock_install_seed_skills):
#         """Test the main block execution."""
#         mock_home.return_value = pathlib.Path("/home/testuser")

#         # Import the module to trigger the main block
#         import eurekaclaw.skills.install

#         expected_dir = pathlib.Path("/home/testuser") / ".eurekaclaw" / "skills"
#         mock_install_from_hub.assert_called_once_with("self-improving-agent", expected_dir)
#         mock_install_seed_skills.assert_called_once_with(expected_dir)