require_relative '../../support/axel_pong_doubles_audio'
[[0,1,0,1],[0,0,1,1],[1,0,1,0]].each do |teams|
  4.times do |viewer|
    with_audio do |audio,program|
      program.pong_preferences=program.pong_preferences.merge('doubles_sounds'=>'personal')
      state=snapshot(teams)
      state['fx']=[[1,'step',viewer,state['p'][viewer],teams[viewer]*20]]
      audio.update(state,viewer:viewer,paused:false)
      assert(program.played.include?('pong_move'),'Personal own movement changed with team position')
      state['fx']=[[2,'hit',viewer,state['p'][viewer],teams[viewer]*20]]
      audio.update(state,viewer:viewer,paused:false)
      near(program.voice('pong_hit',viewer).frequency,44100,'Personal own contact pitch changed')
      partner=teams.each_index.find{|seat|seat!=viewer && teams[seat]==teams[viewer]}
      state['fx']=[[3,'step',partner,state['p'][partner],teams[partner]*20]]
      audio.update(state,viewer:viewer,paused:false)
      assert(program.played.last=='pong_move_double','Partner did not use the contrasting steps')
      state['fx']=[[4,'hit',partner,state['p'][partner],teams[partner]*20]]
      audio.update(state,viewer:viewer,paused:false)
      near(program.voice('pong_op_hit',partner).frequency,44100*GameRoomPong::Audio::DOUBLES_FIRST_PLAYER_PITCH,'Partner contact did not contrast')
      opponent=teams.each_index.find{|seat|teams[seat]!=teams[viewer]}
      state['fx']=[[5,'hit',opponent,state['p'][opponent],teams[opponent]*20]]
      audio.update(state,viewer:viewer,paused:false)
      near(program.voice('pong_op_hit',opponent).frequency,44100*identity_pitch(teams,opponent),'Personal mode changed opponents')
    end
  end
end
puts 'PASS personal doubles audio: consistent own footsteps/contact in every seat, contrasting partner and unchanged opponents'
