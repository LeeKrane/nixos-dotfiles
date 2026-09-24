# NVIDIA's static security scanner for Claude Code / Cursor agent skills
# (SKILL.md files, tool manifests, etc). Not in nixpkgs. Pinned to the
# latest release tag. To bump: check
# `git ls-remote --tags https://github.com/NVIDIA/SkillSpector`, then set
# `version` and take `hash` from `nix-prefetch-url --unpack
# https://github.com/NVIDIA/SkillSpector/archive/refs/tags/v<version>.tar.gz`.
#
# Upstream's *required* dependency list (not just its optional `mcp` /
# `langgraph-dev` extras) pulls in the full langchain/langgraph/boto3/openai
# stack, used only for its optional `--llm-provider` semantic-analysis path
# (`cli.py` imports it lazily, so `scan --no-llm` never touches it or any
# API key at runtime). nixpkgs already carries all of it.
#
# pywhatwgurl is the one dependency missing from nixpkgs, so it's packaged
# inline below straight from its PyPI wheel: its sdist relies on hatch-vcs
# for its version string, which needs git metadata that isn't present when
# fetched standalone; the wheel sidesteps that entirely.
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
let
  pywhatwgurl = python3Packages.buildPythonPackage rec {
    pname = "pywhatwgurl";
    version = "0.1.1";
    format = "wheel";

    src = python3Packages.fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-1nBy0/cC+Jnm5d4HTn+hS1ycXIX2FsYBbE7vnJQRPV8=";
    };

    propagatedBuildInputs = [ python3Packages.idna ];

    doCheck = false;
    pythonImportsCheck = [ "pywhatwgurl" ];

    meta = {
      description = "Pure Python implementation of the WHATWG URL Standard";
      homepage = "https://github.com/pywhatwgurl/pywhatwgurl";
      license = lib.licenses.mit;
    };
  };
in
python3Packages.buildPythonApplication (finalAttrs: {
  pname = "skillspector";
  version = "2.12.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "SkillSpector";
    tag = "v${finalAttrs.version}";
    hash = "sha256-q/JclOy2+Z6oGeKn7bZa8njJHRF8SNUBPsj46IPfn9Q=";
  };

  build-system = [ python3Packages.hatchling ];

  # typer's upstream pin (<0.24) only exists to dodge a click version clash
  # with a dev-only tool that isn't part of our closure; nixpkgs' typer
  # (0.25+) scans fine. regex's exact `==` pin just trails nixpkgs' newer
  # calendar-versioned release.
  pythonRelaxDeps = [
    "typer"
    "regex"
  ];

  dependencies = with python3Packages; [
    typer
    rich
    httpx
    pywhatwgurl
    regex
    packaging
    pyyaml
    pydantic
    openai
    langgraph
    langchain-anthropic
    langchain-aws
    langchain-core
    langchain-openai
    boto3
    langsmith
    yara-python
  ];

  pythonImportsCheck = [ "skillspector" ];

  # Upstream's suite covers the full LLM-analysis graph and its own
  # provider integrations (tests/integration, tests/provider); pytest's
  # addopts already skip those marks, but the remainder still wants the
  # unpackaged `dev` extras (pytest-asyncio, ruff, mypy, ...). Skip and
  # rely on pythonImportsCheck plus a manual `--help`/`scan` smoke test.
  doCheck = false;

  meta = {
    description = "Static security scanner for Claude Code / Cursor agent skills";
    homepage = "https://github.com/NVIDIA/SkillSpector";
    license = lib.licenses.asl20;
    mainProgram = "skillspector";
    platforms = lib.platforms.unix;
  };
})
