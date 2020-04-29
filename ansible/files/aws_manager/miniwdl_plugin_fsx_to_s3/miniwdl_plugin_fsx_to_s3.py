# This miniwdl plugin installs on the AWS swarm manager. Upon success of a top-level run, it writes
# the output files to the linked S3 bucket by invoking the fsx_to_s3 utility (which comes with the
# aws_fsx_lustre_client role) on the output_links folder. It also writes the log, and a version of
# the outputs JSON with the local File paths rewritten using the S3 URIs (outputs.s3.json). The URI
# to outputs.s3.json is injected into the local run outputs.
# These functions can be disabled for a run by setting environment MINIWDL__FSX_TO_S3__ENABLE=false
import os
import subprocess
import json
import WDL
from WDL._util import StructuredLogMessage as _


def task(cfg, logger, run_id_stack, run_dir, task, **recv):
    logger = logger.getChild("fsx_to_s3")
    # do nothing with inputs
    recv = yield recv
    # do nothing with container
    recv = yield recv
    # after container exit: if appropriate (top-level run & user hasn't opted out), write output
    # files back to S3, including an outputs.s3.json with rewritten Files
    if (
        len(run_id_stack) == 1
        and not run_id_stack[0].startswith("download-")
        and cfg["fsx_to_s3"].get_bool("auto")
    ):
        logger.info("writing task outputs to S3")
        uploaded = fsx_to_s3(logger, run_dir, ["task.log", "output_links"])
        outputs_s3_json = write_outputs_s3_json(
            logger, recv["outputs"], run_dir, uploaded, task.name
        )
        # inject output
        recv["outputs"] = recv["outputs"].bind("_outputs_s3_json", WDL.Value.File(outputs_s3_json))
    # yield back outputs
    yield recv


def workflow(cfg, logger, run_id_stack, run_dir, workflow, **recv):
    logger = logger.getChild("fsx_to_s3")
    # do nothing with inputs
    recv = yield recv
    # after workflow completion:
    if len(run_id_stack) == 1 and cfg["fsx_to_s3"].get_bool("auto"):
        logger.info("writing workflow outputs to S3")
        uploaded = fsx_to_s3(logger, run_dir, ["workflow.log", "output_links"])
        outputs_s3_json = write_outputs_s3_json(
            logger, recv["outputs"], run_dir, uploaded, workflow.name
        )
        recv["outputs"] = recv["outputs"].bind("_outputs_s3_json", WDL.Value.File(outputs_s3_json))
    # yield back outputs
    recv = yield recv


def fsx_to_s3(logger, run_dir, files):
    files = [os.path.join(run_dir, fn) for fn in files]
    files = [fn for fn in files if os.path.exists(fn)]
    try:
        logger.debug(_("writing", files=files))
        proc = subprocess.run(
            ["fsx_to_s3"] + files,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            universal_newlines=True,
        )
    except subprocess.CalledProcessError as exn:
        logger.error(_("failed writing output file(s) to S3", stderr=proc.stderr))
        raise WDL.Error.RuntimeError("failed writing output file(s) to S3") from exn
    # read stdout table of local filenames & uploaded URIs
    ans = {}
    for line in proc.stdout.split("\n"):
        line = line.strip()
        if line:
            line = line.split("\t")
            if line:
                assert len(line) == 2 and line[0] not in ans
                logger.info(_("wrote", uri=line[1], size=os.path.getsize(line[0])))
                ans[line[0]] = line[1]
    return ans


def write_outputs_s3_json(logger, outputs, run_dir, uploaded, namespace):
    # rewrite uploaded files to their S3 URIs
    def rewriter(fn):
        try:
            return uploaded[fn]
        except KeyError:
            logger.warning(
                _(
                    "output file wasn't written to S3; keeping local path in outputs.s3.json",
                    file=fn,
                )
            )
            return fn

    outputs_s3 = WDL.Value.rewrite_env_files(outputs, rewriter)
    outputs_s3_json = WDL.values_to_json(outputs_s3, namespace=namespace)

    # drop outputs.s3.json in run directory
    fn = os.path.join(run_dir, "outputs.s3.json")
    WDL._util.write_atomic(json.dumps(outputs_s3_json, indent=2), fn)
    # write it to S3 too, returning S3 URI of outputs.s3.json
    return next(iter(fsx_to_s3(logger, run_dir, files=["outputs.s3.json"]).values()))
