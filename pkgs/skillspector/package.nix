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

  doCheck = false;

  meta = {
    description = "Static security scanner for Claude Code / Cursor agent skills";
    homepage = "https://github.com/NVIDIA/SkillSpector";
    license = lib.licenses.asl20;
    mainProgram = "skillspector";
    platforms = lib.platforms.unix;
  };
})
