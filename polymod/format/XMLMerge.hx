package polymod.format;

import polymod.util.Util;

class XMLMerge
{
  public static function mergeXMLWork(a:Xml, b:Xml, children:Bool = true, attributes:Bool = true)
  {
    if (a == null || b == null) return;

    if (a.nodeType == Xml.XmlType.Document)
    {
      a = a.firstElement();
    }
    if (b.nodeType == Xml.XmlType.Document)
    {
      b = b.firstElement();
    }

    if (a.nodeType != Xml.XmlType.Element || b.nodeType != Xml.XmlType.Element)
    {
      return;
    }

    if (a.nodeName == 'merge' || b.nodeName == 'merge') return;

    if (children)
    {
      for (el in b.elements())
      {
        if (el == null) continue;
        if (el.nodeName == 'merge') continue;

        var aCount = countNodes(a, el.nodeName);
        var bCount = countNodes(b, el.nodeName);

        if (aCount == 0 && bCount > 0)
        {
          a.addChild(Util.copyXml(el));
        }
        else if (countNodes(a, el.nodeName) == 1 && countNodes(b, el.nodeName) == 1)
        {
          mergeXMLWork(a.elementsNamed(el.nodeName).next(), el);
        }
        else
        {
          a.addChild(Util.copyXml(el));
        }
      }
    }
    if (attributes)
    {
      for (att in b.attributes())
      {
        a.set(att, b.get(att));
      }
    }
  }

  public static function countNodes(xml:Xml, nodeName:String):Int
  {
    var i = 0;
    for (el in xml.elementsNamed(nodeName))
    {
      i++;
    }
    return i;
  }

  public static function mergeXML(a:Xml, b:Xml, allSigs:Array<String>, mergeMap:Map<String, Array<String>>):Void
  {
    var aName = a.nodeType == Xml.XmlType.Document ? '' : a.nodeName;
    var bName = b.nodeType == Xml.XmlType.Document ? '' : b.nodeName;

    if (aName != bName) return;

    var aSig = getNodeSignature(a);
    var bSig = getNodeSignature(b);

    if (aSig != bSig) return;

    for (sig in allSigs)
    {
      if (sig.indexOf(aSig) == 0)
      {
        if (sig == aSig)
        {
          // we have reached a terminal point
          var keyValues = mergeMap.get(sig);
          if (keyValues == null)
          {
            if (sig == '' && aSig == '')
            {
              if (a.nodeType == Xml.XmlType.Document && b.nodeType == Xml.XmlType.Document)
              {
                var a = a.firstElement();
                var b = b.firstElement();
                mergeXML(a, b, allSigs, mergeMap);
              }
              else
              {
                return;
              }
            }
          }
          if (keyValues != null && keyValues.length % 2 == 0 && keyValues.length >= 2)
          {
            for (i in 0...Std.int(keyValues.length / 2))
            {
              var key = keyValues[(i * 2)];
              var value = keyValues[(i * 2) + 1];
              var aValue = a.get(key);
              if (aValue == value)
              {
                mergeXMLWork(a, b);
              }
            }
          }
        }
        else
        {
          // descend upon all children
          for (aEl in a.elements())
          {
            for (bEl in b.elements())
            {
              mergeXML(aEl, bEl, allSigs, mergeMap);
            }
          }
        }
      }
    }
  }

  public static function mergeXMLNodes(a:Xml, b:Xml)
  {
    if (b == null) return;

    var allSigs = [''];
    var bMap:Map<String, Array<String>> = getNodeMergeMap(b, allSigs);

    mergeXML(a, b, allSigs, bMap);
  }

  public static function getNodeMergeMap(xml:Xml, addToArray:Array<String>):Map<String, Array<String>>
  {
    var map:Map<String, Array<String>> = new Map<String, Array<String>>();

    if (xml == null) return map;

    for (el in xml.elements())
    {
      if (el.nodeName == 'merge') continue;
      var subMap = getNodeMergeMap(el, addToArray);
      map = mergeMapsDestructively(map, subMap);
      var sig = getNodeSignature(el);

      var f:haxe.xml.Access = new haxe.xml.Access(el);
      if (f.hasNode.merge)
      {
        if (map.exists(sig) == false)
        {
          map.set(sig, []);
        }
        var arr = map.get(sig);

        var mergeKey = f.node.merge.has.key ? f.node.merge.att.key : '';
        var mergeKeyValue = f.node.merge.x.get(mergeKey);

        arr.push(mergeKey);
        arr.push(mergeKeyValue);

        if (addToArray.indexOf(sig) == -1)
        {
          addToArray.push(sig);
        }
      }
    }

    return map;
  }

  public static function getNodeSignature(xml:Xml):String
  {
    var arr = [];
    var parent = xml;
    while (parent != null && parent.nodeType == Xml.XmlType.Element)
    {
      arr.push(parent.nodeName);
      if (parent.nodeType == Xml.XmlType.Element)
      {
        parent = parent.parent;
      }
      else
      {
        parent = null;
      }
    }
    var str = '';
    for (i in 0...arr.length)
    {
      var j = arr.length - 1 - i;
      str += arr[j];
      if (i != arr.length - 1)
      {
        str += '.';
      }
    }
    return str;
  }

  static function mergeMapsDestructively(a:Map<String, Array<String>>, b:Map<String, Array<String>>):Map<String, Array<String>>
  {
    if (a == null) a = new Map<String, Array<String>>();
    if (b == null) return a;
    for (bkey in b.keys())
    {
      if (a.exists(bkey))
      {
        var aArr = a.get(bkey);
        var bArr = b.get(bkey);
        for (bVal in bArr)
        {
          aArr.push(bVal);
        }
      }
      else
      {
        var bArr = b.get(bkey);
        a.set(bkey, bArr);
        b.remove(bkey);
      }
    }
    return a;
  }
}
