import sys
import xml.etree.ElementTree as ET
from xml.dom import minidom

def generate_xml(hostnames, ips):
    hostname_list = hostnames.split(',')
    ip_list = ips.split(',')

    root = ET.Element("ROOT")
    
    cluster = ET.SubElement(root, "CLUSTER")
    ET.SubElement(cluster, "PARAM", name="clusterName", value="Gbase8c_cluster")
    ET.SubElement(cluster, "PARAM", name="nodeNames", value=','.join(hostname_list))
    ET.SubElement(cluster, "PARAM", name="gaussdbAppPath", value="/opt/database/install/app")
    ET.SubElement(cluster, "PARAM", name="gaussdbLogPath", value="/opt/log/omm")
    ET.SubElement(cluster, "PARAM", name="tmpMppdbPath", value="/opt/database/tmp")
    ET.SubElement(cluster, "PARAM", name="gaussdbToolPath", value="/opt/database/install/om")
    ET.SubElement(cluster, "PARAM", name="corePath", value="/opt/database/corefile")
    ET.SubElement(cluster, "PARAM", name="backIp1s", value=','.join(ip_list))
    ET.SubElement(cluster, "PARAM", name="sshPort", value="22")

    devicelist = ET.SubElement(root, "DEVICELIST")
    for i, hostname in enumerate(hostname_list):
        data_node_value = "/data/database/install/data/dn"
        device = ET.SubElement(devicelist, "DEVICE", sn=hostname)
        ET.SubElement(device, "PARAM", name="name", value=hostname)
        ET.SubElement(device, "PARAM", name="azName", value="AZ1")
        ET.SubElement(device, "PARAM", name="azPriority", value="1")
        ET.SubElement(device, "PARAM", name="backIp1", value=ip_list[i])
        ET.SubElement(device, "PARAM", name="sshIp1", value=ip_list[i])
        if len(hostname_list) != 1:
            additional_nodes = ",".join([f"{hn},/data/database/install/data/dn" for hn in hostname_list[1:]])
            data_node_value += f",{additional_nodes}"
        if i == 0:
            ET.SubElement(device, "PARAM", name="dataNum", value="1")
            ET.SubElement(device, "PARAM", name="dataPortBase", value="15400")
            ET.SubElement(device, "PARAM", name="dataNode1", value=data_node_value)
            ET.SubElement(device, "PARAM", name="dataNode1_syncNum", value="0")
        ''' not use cm server
            ET.SubElement(device, "PARAM", name="cmDir", value="/opt/database/install/cm")
            ET.SubElement(device, "PARAM", name="cmsNum", value="1")
            ET.SubElement(device, "PARAM", name="cmServerPortBase", value="15300")
            ET.SubElement(device, "PARAM", name="cmServerListenIp1", value=','.join(ip_list))
            ET.SubElement(device, "PARAM", name="cmServerHaIp1", value=','.join(ip_list))
            ET.SubElement(device, "PARAM", name="cmServerlevel", value="1")
            ET.SubElement(device, "PARAM", name="cmServerRelation", value=','.join(hostname_list))
            #ET.SubElement(device, "PARAM", name="cmServerPortStandby", value="15300")
        '''
    xml_str = ET.tostring(root, encoding='utf-8')
    parsed_str = minidom.parseString(xml_str)
    pretty_xml_as_str = parsed_str.toprettyxml(indent="  ")

    with open("/home/gbase/cluster.xml", "w", encoding="utf-8") as f:
        f.write(pretty_xml_as_str)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python generate_xml.py <hostname_list> <ip_list>")
        sys.exit(1)

    hostnames = sys.argv[1]
    ips = sys.argv[2]

    generate_xml(hostnames, ips)
