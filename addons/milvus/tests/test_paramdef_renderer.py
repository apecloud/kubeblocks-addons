import pathlib
import subprocess
import yaml

ROOT = pathlib.Path(__file__).resolve().parents[3]

def main():
    result = subprocess.run(["helm", "template", "milvus", str(ROOT / "addons/milvus")], check=True, capture_output=True, text=True)
    docs = [doc for doc in yaml.safe_load_all(result.stdout) if doc]
    pd = next(d for d in docs if d.get("kind") == "ParametersDefinition")
    pcr = next(d for d in docs if d.get("kind") == "ParamConfigRenderer")
    assert set(pd["spec"]) == {"fileName", "parametersSchema", "staticParameters"}
    assert pd["spec"]["fileName"] == "user.yaml"
    assert pcr["spec"]["componentDef"] == "^milvus-standalone-"
    assert pcr["spec"]["parametersDefs"] == [pd["metadata"]["name"]]
    assert pcr["spec"]["configs"] == [{"name": "user.yaml", "templateName": "config", "fileFormatConfig": {"format": "yaml"}}]

if __name__ == "__main__":
    main()
