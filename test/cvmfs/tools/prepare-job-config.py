"""Require a container for the fixture using the image's real Slurm destination."""
import sys
import xml.etree.ElementTree as ET

source, target = sys.argv[1:]
tree = ET.parse(source)
root = tree.getroot()
destination = root.find("./destinations/destination[@id='slurm_cluster_singularity']")
if destination is None:
    raise RuntimeError("The appliance has no slurm_cluster_singularity destination")
ET.SubElement(destination, "param", id="require_container").text = "true"
tools = root.find("tools")
if tools is None:
    tools = ET.SubElement(root, "tools")
ET.SubElement(tools, "tool", id="cvmfs_seqtk_smoke", destination="slurm_cluster_singularity")
ET.SubElement(tools, "tool", id="upload1", destination="local_no_container")
tree.write(target, encoding="utf-8", xml_declaration=True)
