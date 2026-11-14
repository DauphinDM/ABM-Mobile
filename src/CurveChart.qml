import QtQuick

Canvas {
    id: chart
    property var points: []
    implicitHeight: 140
    Accessible.role: Accessible.Graphic
    Accessible.name: qsTr("Supported engine torque curve. Game readback, not a dyno result.")
    onPointsChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx=getContext("2d"); ctx.reset(); ctx.clearRect(0,0,width,height)
        var data=points.filter(function(p){return p && isFinite(p.rpm) && isFinite(p.torque)})
        if(data.length<2) return
        var maxRPM=1,minT=0,maxT=1
        data.forEach(function(p){ maxRPM=Math.max(maxRPM,p.rpm); minT=Math.min(minT,p.torque); maxT=Math.max(maxT,p.torque) })
        ctx.strokeStyle="#ffd60a"; ctx.lineWidth=2; ctx.beginPath()
        data.forEach(function(p,i){ var x=2+p.rpm/maxRPM*(width-4),y=height-4-(p.torque-minT)/Math.max(1,maxT-minT)*(height-8); if(i===0) ctx.moveTo(x,y); else ctx.lineTo(x,y) })
        ctx.stroke()
    }
}
